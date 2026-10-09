//
//  DockStation.swift
//  Dock Finder
//
//  Result types for every on-device feature. Each one produces a single
//  sentence that Siri speaks and the app displays.
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
    /// Straight-line ("as the crow flies") distance in meters from wherever
    /// the search was centered. This is not a walking or cycling route distance.
    let straightLineDistance: CLLocationDistance
    /// When the station last reported its availability, if the feed provides it.
    let observedAt: Date?

    var spokenName: String { Speech.stationName(name) }
}

/// A place to find docks near: a saved place or a map search result.
nonisolated struct Destination: Codable, Sendable, Equatable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    /// A short street address, when known, for display only.
    var address: String? = nil

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// What every feature hands to Siri and the UI.
nonisolated struct DockAnswer: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        /// Plain on-device logic over Citi Bike's live feed.
        case onDevice
        /// Understood by Apple's on-device language model, then answered on device.
        case onDeviceModel
        /// Answered by the n8n backend.
        case server
    }

    let text: String
    /// The station the answer recommends, for directions. `nil` for
    /// answers that aren't about one station (citywide totals, server replies).
    var station: DockStation? = nil
    var source: Source = .onDevice
}

// MARK: - Nearest dock to the rider

nonisolated struct DockSearchResult: Sendable, Equatable {
    let station: DockStation
    /// True when the user granted only approximate location, so the
    /// "nearest" station may not actually be the closest one.
    let locationIsApproximate: Bool

    /// "West 15th and 6th has 53 docks open, right there."
    var summary: String {
        var sentence = "\(station.spokenName) has \(Speech.docksOpen(station.availableDocks)), \(Speech.distance(station.straightLineDistance))."
        if locationIsApproximate {
            sentence += " Your location is approximate, so a closer dock may exist."
        }
        return sentence
    }

    var answer: DockAnswer { DockAnswer(text: summary, station: station) }
}

// MARK: - Dock near a destination

nonisolated struct DestinationDockResult: Sendable, Equatable {
    let destination: Destination
    /// The rider's usual dock for this destination, if one is set and still exists.
    let usualDock: StationSnapshot?
    /// Why the usual dock isn't good right now; `nil` if it's fine or unset.
    let usualDockProblem: StationProblem?
    /// Where to go. Distance is measured from the destination.
    let selected: DockStation?
    /// True when `selected` is the rider's backup dock for this place.
    var selectedIsBackup = false

    var usesUsualDock: Bool { usualDock != nil && usualDockProblem == nil }

    var summary: String {
        let lead = usualDockProblem.map { "Your usual dock \($0.phrase). " } ?? ""
        guard let selected else {
            return lead + "No docks with space near \(destination.name)."
        }
        if usesUsualDock {
            return "Your usual dock has \(Speech.docksOpen(selected.availableDocks))."
        }
        let distance = Speech.distance(selected.straightLineDistance, from: destination.name)
        if selectedIsBackup {
            return lead + "Your backup, \(selected.spokenName), has \(Speech.docksOpen(selected.availableDocks)), \(distance)."
        }
        if let usualDockProblem {
            return "Your usual dock \(usualDockProblem.phrase). Go to \(selected.spokenName), \(selected.availableDocks) docks, \(distance)."
        }
        return "\(selected.spokenName) has \(Speech.docksOpen(selected.availableDocks)), \(distance)."
    }

    var answer: DockAnswer { DockAnswer(text: summary, station: selected) }
}

// MARK: - One station's status

nonisolated struct StationCheckResult: Sendable, Equatable {
    let station: StationSnapshot
    /// `nil` when the station has room.
    let problem: StationProblem?
    /// The nearest station with room, if the requested one doesn't have any.
    let alternative: DockStation?

    var summary: String {
        let name = station.spokenName
        guard let problem else {
            return "\(name) has \(Speech.docksOpen(station.openDocks)) and \(Speech.bikes(station.bikesAvailable))."
        }
        guard let alternative else {
            return "\(name) \(problem.phrase), and nothing nearby has space."
        }
        return "\(name) \(problem.phrase). Go to \(alternative.spokenName), \(alternative.availableDocks) docks, \(Speech.distance(alternative.straightLineDistance))."
    }

    var answer: DockAnswer {
        let target = problem == nil
            ? DockStation(snapshot: station, distance: 0)
            : alternative
        return DockAnswer(text: summary, station: target)
    }
}

// MARK: - Citywide totals

nonisolated struct NetworkSummary: Sendable, Equatable {
    var bikesAvailable = 0
    var ebikesAvailable = 0
    var openDocks = 0
    var activeStations = 0
    /// Installed, accepting returns, and zero open docks.
    var fullStations = 0

    /// "35,393 bikes and 30,882 open docks citywide. 243 stations are full."
    var summary: String {
        let full = fullStations == 1 ? "1 station is full." : "\(Speech.number(fullStations)) stations are full."
        return "\(Speech.number(bikesAvailable)) bikes and \(Speech.number(openDocks)) open docks citywide. \(full)"
    }

    var answer: DockAnswer { DockAnswer(text: summary) }
}
