//
//  DockStation.swift
//  Dock Finder
//

import CoreLocation
import Foundation

/// A Citi Bike station that is currently accepting returns.
nonisolated struct DockStation: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let availableDocks: Int
    /// Straight-line ("as the crow flies") distance from the user, in meters.
    /// This is not a walking or cycling route distance.
    let straightLineDistance: CLLocationDistance
    /// When the station last reported its availability, if the feed provides it.
    let observedAt: Date?
}

/// The outcome of a dock search, shared by Siri and the in-app UI.
nonisolated struct DockSearchResult: Sendable, Equatable {
    let station: DockStation
    /// True when the user granted only approximate location, so the
    /// "nearest" station may not actually be the closest one.
    let locationIsApproximate: Bool

    /// The sentence Siri speaks and the app displays.
    var summary: String {
        let distance = Measurement(value: station.straightLineDistance, unit: UnitLength.meters)
            .formatted(.measurement(width: .wide, usage: .road))
        let docks = station.availableDocks == 1 ? "1 open dock" : "\(station.availableDocks) open docks"
        var sentence = "The nearest available dock is at \(station.name), about \(distance) away in a straight line, with \(docks)."
        if locationIsApproximate {
            sentence += " Your location is approximate, so a closer dock may exist."
        }
        return sentence
    }
}
