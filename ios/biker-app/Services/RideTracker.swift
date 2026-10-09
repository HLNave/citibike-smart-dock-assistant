//
//  RideTracker.swift
//  Dock Finder
//
//  Watches an active ride in the background and, once the rider is within
//  the alert distance of the destination, speaks the best dock and posts
//  it as a notification. Two location sources run together:
//
//  - Live location updates, like a navigation app, for an on-time alert.
//  - A geofence (CLMonitor) around the destination, which relaunches the
//    app on arrival even if iOS terminated it during the ride.
//
//  Both need Always location access to work with the phone locked. The
//  ride is saved, so tracking resumes after a relaunch.
//

import CoreLocation
import Foundation
import Observation
import UIKit

nonisolated struct RideArrival: Equatable, Sendable {
    let destination: String
    let answer: DockAnswer
    let date: Date
}

/// What the assistant needs to start and end rides. Abstracted for testing.
protocol RideControlling: AnyObject {
    var currentRide: Ride? { get }
    /// True when rides can be tracked with the phone locked (Always location).
    var canTrackInBackground: Bool { get }
    func start(_ ride: Ride) async
    func end() async
}

@Observable
final class RideTracker: RideControlling {
    static let shared = RideTracker()

    nonisolated static let storageKey = "activeRide"
    private static let monitorName = "DockFinderRide"
    private static let destinationConditionID = "destination"

    /// The ride being tracked, if any.
    private(set) var currentRide: Ride?
    /// Latest straight-line distance to the destination, for the app's ride card.
    private(set) var distanceRemaining: CLLocationDistance?
    /// What was said on the last arrival, shown in the app afterwards.
    private(set) var lastArrival: RideArrival?

    private let defaults: UserDefaults
    private let announcer = Announcer()
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var monitor: CLMonitor?
    private var tasks: [Task<Void, Never>] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentRide = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Ride.self, from: $0) }
    }

    var canTrackInBackground: Bool {
        LocationService.shared.authorizationStatus == .authorizedAlways
    }

    // MARK: - Starting and ending

    func start(_ ride: Ride) async {
        await stopTracking()
        currentRide = ride
        distanceRemaining = nil
        lastArrival = nil
        save()
        await Announcer.requestNotificationPermission()
        await beginTracking(ride)
    }

    func end() async {
        currentRide = nil
        distanceRemaining = nil
        save()
        await stopTracking()
    }

    /// Call at every launch, including the background relaunch iOS does for
    /// a geofence event, so tracking picks up where it left off.
    func resume() async {
        guard let ride = currentRide, tasks.isEmpty else { return }
        if ride.hasExpired() {
            await end()
        } else {
            await beginTracking(ride)
        }
    }

    func dismissLastArrival() {
        lastArrival = nil
    }

    // MARK: - Tracking

    private func beginTracking(_ ride: Ride) async {
        // Declares that background use relies on Always authorization; must
        // be held for live updates and geofence events while not in use.
        serviceSession = CLServiceSession(authorization: .always)
        // With only While Using access, a background activity session keeps
        // updates flowing after the app leaves the screen. It can only start
        // while the app is in the foreground, and shows the blue location pill.
        if UIApplication.shared.applicationState == .active {
            backgroundSession = CLBackgroundActivitySession()
        }

        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        await monitor.add(
            CLMonitor.CircularGeographicCondition(center: ride.destination.location.coordinate, radius: ride.alertDistance),
            identifier: Self.destinationConditionID,
            assuming: .unsatisfied
        )

        tasks.append(Task { [weak self] in
            do {
                for try await event in await monitor.events
                where event.identifier == Self.destinationConditionID && event.state == .satisfied {
                    await self?.arrive()
                    return
                }
            } catch {}
        })

        tasks.append(Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, let ride = self.currentRide else { return }
                    switch ride.progress(at: update.location) {
                    case .arrived:
                        await self.arrive()
                        return
                    case .expired:
                        await self.end()
                        return
                    case .riding(let distance):
                        if let distance { self.distanceRemaining = distance }
                    }
                }
            } catch {}
        })

        tasks.append(Task { [weak self] in
            let remaining = ride.expiresAt.timeIntervalSinceNow
            try? await Task.sleep(for: .seconds(max(remaining, 0)))
            guard !Task.isCancelled, let self, self.currentRide == ride else { return }
            await self.end()
        })
    }

    private func stopTracking() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let monitor {
            await monitor.remove(Self.destinationConditionID)
        }
        monitor = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// Says where to dock, once per ride.
    ///
    /// Tracking is stopped only after the answer has been spoken: the
    /// location session is what keeps the app running in the background,
    /// and this runs inside one of the tracking tasks, so stopping first
    /// would cancel the Citi Bike request mid-flight.
    private func arrive() async {
        guard let ride = currentRide else { return }
        currentRide = nil
        distanceRemaining = nil
        save()

        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Ride arrival")
        // A separate task, so cancelling the tracking tasks can't cancel it.
        let answer = await Task { await Self.arrivalAnswer(for: ride) }.value
        lastArrival = RideArrival(destination: ride.destination.name, answer: answer, date: .now)
        await announcer.announce(answer.text, title: "Docking near \(ride.destination.name)")

        await stopTracking()
        UIApplication.shared.endBackgroundTask(backgroundTask)
    }

    /// Uses the saved place's current docks, in case they changed mid-ride.
    /// Failures become a spoken explanation rather than silence.
    private static func arrivalAnswer(for ride: Ride) async -> DockAnswer {
        do {
            if let id = ride.savedPlaceID, let place = SavedPlacesStore.shared.place(id: id) {
                return try await DockFinderService.live.findDock(for: place).answer
            }
            return try await DockFinderService.live.findDock(near: ride.destination).answer
        } catch let error as DockFinderError {
            return DockAnswer(text: String(localized: error.localizedStringResource))
        } catch {
            return DockAnswer(text: String(localized: DockFinderError.networkUnavailable.localizedStringResource))
        }
    }

    private func save() {
        if let currentRide, let data = try? JSONEncoder().encode(currentRide) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
