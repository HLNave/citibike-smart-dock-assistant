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

nonisolated protocol PlaceSearching: Sendable {
    /// Best matches first. Throws `DockFinderError.placeNotFound` when nothing matches.
    func search(_ query: String) async throws -> [Destination]
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
}
