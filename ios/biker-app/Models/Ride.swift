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

    init(
        destination: Destination,
        savedPlaceID: UUID? = nil,
        alertDistance: CLLocationDistance = SavedPlace.defaultAlertDistance,
        startedAt: Date = .now,
        duration: TimeInterval = Ride.maxDuration
    ) {
        self.destination = destination
        self.savedPlaceID = savedPlaceID
        self.alertDistance = alertDistance
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(duration)
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
