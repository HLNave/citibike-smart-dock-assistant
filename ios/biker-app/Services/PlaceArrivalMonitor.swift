//
//  PlaceArrivalMonitor.swift
//  Dock Finder
//
//  Tells the rider where to dock when they bike up to a saved place, even
//  if they never started a ride. iOS watches a circle (geofence) around
//  each saved place at its alert distance and wakes Dock Finder when the
//  rider crosses into one, even if the app wasn't running. The app then
//  checks that they were actually biking (not walking or on the subway),
//  speaks the dock answer and posts it as a notification.
//
//  Needs Always location access. Motion & Fitness access lets it skip
//  walking and transit; without it, every arrival alerts.
//

import CoreLocation
import CoreMotion
import Foundation
import UIKit

final class PlaceArrivalMonitor {
    static let shared = PlaceArrivalMonitor()

    private static let monitorName = "DockFinderSavedPlaces"
    private static let lastAlertsKey = "placeArrivalLastAlerts"

    private let announcer = Announcer()
    /// Shared so concurrent syncs never create two monitors with the same
    /// name, which iOS doesn't allow.
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?

    /// Call at every launch, including the background relaunch iOS does
    /// for a geofence, and whenever saved places or permissions change.
    func sync() async {
        let monitor = await currentMonitor()
        let places = SavedPlacesStore.shared.places.filter(\.arrivalAlerts)
        let wanted = Set(places.map(\.id.uuidString))

        for identifier in await monitor.identifiers where !wanted.contains(identifier) {
            await monitor.remove(identifier)
        }
        for place in places {
            let identifier = place.id.uuidString
            if let record = await monitor.record(for: identifier),
               let existing = record.condition as? CLMonitor.CircularGeographicCondition,
               existing.center.latitude == place.latitude,
               existing.center.longitude == place.longitude,
               existing.radius == place.alertDistance {
                continue
            }
            // A new or moved place. Assume "outside" so arriving triggers it.
            await monitor.add(
                CLMonitor.CircularGeographicCondition(center: place.location.coordinate, radius: place.alertDistance),
                identifier: identifier,
                assuming: .unsatisfied
            )
        }
    }

    private func currentMonitor() async -> CLMonitor {
        if let monitorTask { return await monitorTask.value }
        let task = Task { () -> CLMonitor in
            let monitor = await CLMonitor(Self.monitorName)
            self.listen(to: monitor)
            return monitor
        }
        monitorTask = task
        return await task.value
    }

    private func listen(to monitor: CLMonitor) {
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events where event.state == .satisfied {
                    guard let id = UUID(uuidString: event.identifier) else { continue }
                    await self?.arrived(at: id)
                }
            } catch {}
        }
    }

    // MARK: - Arriving

    private func arrived(at placeID: UUID) async {
        guard let place = SavedPlacesStore.shared.place(id: placeID) else { return }
        // Keep running while this checks motion, fetches docks and speaks.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Saved place arrival")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let now = Date.now
        var lastAlerts = Self.lastAlerts()
        let shouldAlert = PlaceArrivalRules.shouldAlert(
            enabled: place.arrivalAlerts,
            busyWithRideOrDirections: RideTracker.shared.currentRide != nil || GuidanceSession.shared.isActive,
            lastAlert: lastAlerts[placeID.uuidString],
            wasCycling: await MotionCheck.wasCycling(now: now),
            now: now
        )
        guard shouldAlert else { return }
        lastAlerts[placeID.uuidString] = now
        UserDefaults.standard.set(lastAlerts, forKey: Self.lastAlertsKey)

        var text: String
        do {
            let answer = try await DockFinderService.live.findDock(for: place).answer
            text = answer.text
            let here = LocationService.shared.lastKnownLocation
            Metrics.shared.log(
                "place_arrival_alert",
                station: answer.station?.name,
                avoidedStation: answer.avoided?.name,
                location: here,
                details: ["place": place.name, "answer": answer.text]
            )
            SavingsStore.shared.record(answer, from: here, context: "place_arrival")
            if let station = answer.station {
                GuidanceSession.shared.offer(station)
                text += " For directions, say: Hey Siri, direct me with Dock Finder."
            }
        } catch let error as DockFinderError {
            text = String(localized: error.localizedStringResource)
        } catch {
            return
        }
        await announcer.announce(text, title: "Arriving at \(place.name)")
    }

    private static func lastAlerts() -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: lastAlertsKey) as? [String: Date] ?? [:]
    }
}

/// Whether the rider is on a bike, from the phone's motion coprocessor.
nonisolated enum MotionCheck {
    /// `nil` when iOS can't say: no motion hardware, or Motion & Fitness
    /// access is off.
    static func wasCycling(now: Date) async -> Bool? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted: return nil
        default: break
        }
        let manager = CMMotionActivityManager()
        let from = now.addingTimeInterval(-PlaceArrivalRules.activityLookback)
        return await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: from, to: now, to: .main) { activities, error in
                withExtendedLifetime(manager) {}
                guard let activities, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let samples = activities.map {
                    PlaceArrivalRules.ActivitySample(start: $0.startDate, cycling: $0.cycling, confident: $0.confidence != .low)
                }
                continuation.resume(returning: PlaceArrivalRules.wasCycling(samples, now: now))
            }
        }
    }

    /// Shows the Motion & Fitness prompt, if it hasn't been answered yet.
    /// Call while the app is on screen.
    static func requestPermission() async {
        guard CMMotionActivityManager.authorizationStatus() == .notDetermined else { return }
        _ = await wasCycling(now: .now)
    }
}
