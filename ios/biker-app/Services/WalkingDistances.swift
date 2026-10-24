//
//  WalkingDistances.swift
//  Dock Finder
//
//  Real walking distances from a few candidate docks to a destination,
//  from Apple Maps, used to choose which dock to recommend. Maps gets a
//  short time limit; docks it hasn't answered for by then keep their
//  street-grid estimate.
//

import CoreLocation
import Foundation
import MapKit

/// Walking distances from docks to a destination. Abstracted for testing.
nonisolated protocol WalkingDistanceProviding: Sendable {
    /// Walking distance in meters from each station to `destination`, by
    /// station ID. Stations without an answer within `timeLimit` are left out.
    func walkingDistances(
        to destination: CLLocation,
        from stations: [DockStation],
        timeLimit: Duration
    ) async -> [String: CLLocationDistance]
}

/// Never measures anything, so the street-grid estimate is used.
nonisolated struct NoWalkingDistances: WalkingDistanceProviding {
    func walkingDistances(
        to destination: CLLocation,
        from stations: [DockStation],
        timeLimit: Duration
    ) async -> [String: CLLocationDistance] {
        [:]
    }
}

nonisolated struct MapKitWalkingDistances: WalkingDistanceProviding {
    func walkingDistances(
        to destination: CLLocation,
        from stations: [DockStation],
        timeLimit: Duration
    ) async -> [String: CLLocationDistance] {
        guard !stations.isEmpty else { return [:] }
        let collector = WalkingDistanceCollector(expected: stations.count)
        // All requests at once. Whatever has come back when the time limit
        // passes is used; later answers are ignored.
        for station in stations {
            Task {
                let distance = await Self.walkingDistance(from: station.location, to: destination)
                await collector.add(station.id, distance)
            }
        }
        Task {
            try? await Task.sleep(for: timeLimit)
            await collector.finish()
        }
        return await collector.result()
    }

    private static func walkingDistance(from start: CLLocation, to end: CLLocation) async -> CLLocationDistance? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: start, address: nil)
        request.destination = MKMapItem(location: end, address: nil)
        request.transportType = .walking
        return try? await MKDirections(request: request).calculateETA().distance
    }
}

/// Gathers answers until every request is in or the time limit passes,
/// whichever comes first.
private actor WalkingDistanceCollector {
    private var distances: [String: CLLocationDistance] = [:]
    private var remaining: Int
    private var finished = false
    private var waiter: CheckedContinuation<[String: CLLocationDistance], Never>?

    init(expected: Int) {
        remaining = expected
    }

    func add(_ stationID: String, _ distance: CLLocationDistance?) {
        guard !finished else { return }
        if let distance { distances[stationID] = distance }
        remaining -= 1
        if remaining <= 0 { finish() }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        waiter?.resume(returning: distances)
        waiter = nil
    }

    func result() async -> [String: CLLocationDistance] {
        if finished { return distances }
        return await withCheckedContinuation { waiter = $0 }
    }
}
