//
//  Ride.swift
//  Dock Finder
//
//  A ride the rider started by voice ("start a ride to school"). While it's
//  active, Dock Finder watches for the rider to come within the alert
//  distance of the destination, then says where to dock.
//

import CoreLocation
import Foundation

nonisolated struct Ride: Codable, Sendable, Equatable {
    /// A ride that never reaches its destination stops tracking after this long.
    static let maxDuration: TimeInterval = 60 * 60

    var destination: Destination
    /// Set when riding to a saved place, so the arrival answer uses that
    /// place's current usual and backup docks.
    var savedPlaceID: UUID?
    var alertDistance: CLLocationDistance
    var startedAt: Date
    var expiresAt: Date
    /// After saying where to dock, guide the rider there turn by turn.
    var guidesToDock: Bool

    init(
        destination: Destination,
        savedPlaceID: UUID? = nil,
        alertDistance: CLLocationDistance = SavedPlace.defaultAlertDistance,
        startedAt: Date = .now,
        duration: TimeInterval = Ride.maxDuration,
        guidesToDock: Bool = false
    ) {
        self.destination = destination
        self.savedPlaceID = savedPlaceID
        self.alertDistance = alertDistance
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(duration)
        self.guidesToDock = guidesToDock
    }

    private enum CodingKeys: String, CodingKey {
        case destination, savedPlaceID, alertDistance, startedAt, expiresAt, guidesToDock
    }

    /// Rides saved by an older version have no `guidesToDock`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destination = try container.decode(Destination.self, forKey: .destination)
        savedPlaceID = try container.decodeIfPresent(UUID.self, forKey: .savedPlaceID)
        alertDistance = try container.decode(CLLocationDistance.self, forKey: .alertDistance)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        guidesToDock = try container.decodeIfPresent(Bool.self, forKey: .guidesToDock) ?? false
    }

    enum Progress: Equatable {
        /// Still on the way; distance to the destination if a fix is known.
        case riding(CLLocationDistance?)
        /// Within the alert distance: time to say where to dock.
        case arrived
        /// Ran past `maxDuration` without arriving.
        case expired
    }

    func progress(at location: CLLocation?, now: Date = .now) -> Progress {
        if now >= expiresAt { return .expired }
        guard let location else { return .riding(nil) }
        let distance = location.distance(from: destination.location)
        return distance <= alertDistance ? .arrived : .riding(distance)
    }

    func hasExpired(now: Date = .now) -> Bool {
        now >= expiresAt
    }
}
