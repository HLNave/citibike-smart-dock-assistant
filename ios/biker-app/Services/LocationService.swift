//
//  LocationService.swift
//  Dock Finder
//
//  One-shot, When In Use location shared by Siri and the app UI.
//  Locations are held only in memory for the duration of a request.
//

import CoreLocation
import Foundation
import UIKit

nonisolated struct LocationFix: Sendable {
    let location: CLLocation
    let isApproximate: Bool
}

nonisolated protocol LocationProviding: Sendable {
    func currentLocation() async throws -> LocationFix
}

@MainActor
final class LocationService: NSObject, LocationProviding {
    static let shared = LocationService()
    /// Set once the "Change to Always Allow" prompt has been asked for.
    /// iOS shows it only once; after that, Settings is the only way.
    nonisolated static let alwaysPromptShownKey = "askedForAlwaysLocation"

    /// How long to wait for Core Location before giving up.
    private static let requestTimeout: Duration = .seconds(15)
    /// A system-cached fix this recent is reused instead of requesting a new one.
    private static let maxCachedLocationAge: TimeInterval = 60

    private let manager = CLLocationManager()
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationContinuations: [CheckedContinuation<CLLocation, Error>] = []
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Requests When In Use permission if the user hasn't decided yet, and
    /// returns the resulting status. Call only from a user interaction.
    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            if authorizationContinuations.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    /// Asks to upgrade to Always, which rides need to track with the phone
    /// locked. iOS shows the prompt at most once; after that the rider has
    /// to change it in Settings.
    func requestAlwaysAuthorization() {
        UserDefaults.standard.set(true, forKey: Self.alwaysPromptShownKey)
        manager.requestAlwaysAuthorization()
    }

    /// Asks for When In Use access, then straight away for Always. iOS
    /// never offers Always in the first prompt; asking for it right after
    /// When In Use is granted shows "Change to Always Allow?" immediately.
    /// Returns the resulting status once the rider has answered.
    func requestAlwaysAuthorizationFromStart() async -> CLAuthorizationStatus {
        let status = await requestWhenInUseAuthorization()
        guard status == .authorizedWhenInUse,
              !UserDefaults.standard.bool(forKey: Self.alwaysPromptShownKey)
        else { return status }
        let prompt = PromptWatcher()
        requestAlwaysAuthorization()
        await prompt.waitForAnswer()
        return manager.authorizationStatus
    }

    nonisolated func currentLocation() async throws -> LocationFix {
        try await fetchCurrentLocation()
    }

    private func fetchCurrentLocation() async throws -> LocationFix {
        switch manager.authorizationStatus {
        case .notDetermined:
            throw DockFinderError.locationPermissionNotDetermined
        case .denied:
            throw DockFinderError.locationPermissionDenied
        case .restricted:
            throw DockFinderError.locationRestricted
        default:
            break
        }

        let isApproximate = manager.accuracyAuthorization == .reducedAccuracy

        if let cached = manager.location,
           cached.horizontalAccuracy >= 0,
           -cached.timestamp.timeIntervalSinceNow <= Self.maxCachedLocationAge {
            return LocationFix(location: cached, isApproximate: isApproximate)
        }

        let location = try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)
            guard locationContinuations.count == 1 else { return }
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.requestTimeout)
                guard !Task.isCancelled else { return }
                self?.finishLocationRequest(.failure(DockFinderError.locationUnavailable))
            }
        }
        return LocationFix(location: location, isApproximate: isApproximate)
    }

    private func finishLocationRequest(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = locationContinuations
        locationContinuations.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }
}

extension LocationService: CLLocationManagerDelegate {
    // CLLocationManager calls its delegate on the thread it was created on,
    // which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = manager.authorizationStatus
            guard status != .notDetermined else { return }
            let continuations = authorizationContinuations
            authorizationContinuations.removeAll()
            continuations.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            finishLocationRequest(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let mapped: DockFinderError = (error as? CLError)?.code == .denied
                ? .locationPermissionDenied
                : .locationUnavailable
            finishLocationRequest(.failure(mapped))
        }
    }
}

/// Waits for a system permission prompt to be answered. Showing the prompt
/// makes the app inactive, and answering it makes it active again. Keeping
/// While Using doesn't change the authorization, so there may be no
/// location callback to wait for. If the prompt never appears, it stops
/// waiting after a couple of seconds.
private final class PromptWatcher {
    private var promptAppeared = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Starts listening right away, so call it before triggering the prompt.
    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.promptAppeared = true }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // Ignore a late "active" from the previous prompt closing.
            MainActor.assumeIsolated { if self?.promptAppeared == true { self?.finish() } }
        })
    }

    func waitForAnswer() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.promptAppeared == false { self?.finish() }
            }
        }
    }

    private func finish() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        continuation?.resume()
        continuation = nil
    }
}
