//
//  PlaceSearch.swift
//  Dock Finder
//
//  Turns "Union Square" or "NYU Stern" into coordinates with Apple's
//  built-in map search. Unlike the backend's OpenStreetMap lookup, it
//  understands landmarks and business names directly, so no AI rewrite
//  step is needed.
//

import CoreLocation
import Foundation
import MapKit
import os

nonisolated protocol PlaceSearching: Sendable {
    /// Best matches first. Throws `DockFinderError.placeNotFound` when nothing matches.
    func search(_ query: String) async throws -> [Destination]
    /// A short street address for a spot, if one can be found.
    func address(for location: CLLocation) async -> String?
}

extension PlaceSearching {
    func address(for location: CLLocation) async -> String? { nil }

    /// `address(for:)`, or nil if it takes longer than `timeout`, so a slow
    /// or offline lookup can't hold up saving a place.
    func address(for location: CLLocation, timeout: Duration) async -> String? {
        await firstValue(within: timeout) { await self.address(for: location) }
    }
}

/// What `operation` returns, or nil once `timeout` passes. Returns at the
/// deadline rather than waiting for a slow operation to notice it was
/// cancelled.
nonisolated func firstValue<T: Sendable>(within timeout: Duration, _ operation: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let pending = OSAllocatedUnfairLock<CheckedContinuation<T?, Never>?>(initialState: continuation)
        let finish: @Sendable (T?) -> Void = { value in
            pending.withLock { waiting in
                defer { waiting = nil }
                return waiting
            }?.resume(returning: value)
        }
        let work = Task { finish(await operation()) }
        Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
            finish(nil)
        }
    }
}

nonisolated struct MapKitPlaceSearch: PlaceSearching {
    /// Citi Bike's service area: Manhattan, Brooklyn, Queens, the Bronx,
    /// Jersey City and Hoboken.
    static let serviceCenter = CLLocation(latitude: 40.7359, longitude: -73.9600)
    static let serviceRegion = MKCoordinateRegion(
        center: serviceCenter.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
    /// Results farther than this from the service center are ignored, so
    /// "Union Square" never resolves to San Francisco.
    static let maxDistanceFromService: CLLocationDistance = 30_000

    func search(_ query: String) async throws -> [Destination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DockFinderError.placeNotFound(query) }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = Self.serviceRegion
        request.resultTypes = [.address, .pointOfInterest]

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            throw DockFinderError.placeNotFound(trimmed)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DockFinderError.networkUnavailable
        }

        let results = response.mapItems.compactMap { item -> Destination? in
            let location = item.location
            guard location.distance(from: Self.serviceCenter) <= Self.maxDistanceFromService else { return nil }
            return Destination(
                name: item.name ?? trimmed,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                address: item.address?.shortAddress
            )
        }
        guard !results.isEmpty else { throw DockFinderError.placeNotFound(trimmed) }
        return results
    }

    func address(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        return item.address?.shortAddress ?? item.name
    }

    /// Straight-line distance from a spot to the nearest Citi Bike station,
    /// so the app can warn when a saved place is outside the service area.
    static func distanceToNearestStation(from location: CLLocation, in stations: [StationInformation]) -> CLLocationDistance? {
        stations
            .map { location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
            .min()
    }
}
