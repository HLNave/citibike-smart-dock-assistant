//
//  LocationService.swift
//  Dock Finder
//
//  One-shot, When In Use location shared by Siri and the app UI.
//  Locations are held only in memory for the duration of a request.
//

import CoreLocation
import Foundation

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
