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
    /// Bikes there to ride away, when known: classic (pedal) and e-bikes.
    var classicBikes: Int? = nil
    var ebikes: Int? = nil

    var spokenName: String { Speech.stationName(name) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// A place to find docks near: a saved place or a map search result.
nonisolated struct Destination: Codable, Sendable, Equatable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    /// A short street address, when known, for display only.
    var address: String? = nil

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// What a spot picked on the map is called until its address is found.
    static let droppedPinName = "Dropped Pin"
    /// What "Use My Current Location" is called when no address is found.
    static let currentLocationName = "Current Location"

    /// The address to save for a place picked here: its street address, or
    /// a search result's own name ("NYU Stern") when it has none. Nil for a
    /// dropped pin or current location whose address wasn't found, rather
    /// than keeping "Dropped Pin" as the place's address for good.
    var savedAddress: String? {
        if let address { return address }
        return [Self.droppedPinName, Self.currentLocationName].contains(name) ? nil : name
    }
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

    /// Which step understood the request, finer than `source`. Sent with
    /// usage data as `answered_by`.
    enum Step: String, Sendable, Equatable {
        /// A fixed action (a Siri phrase or an app button), so there was
        /// nothing to understand.
        case fixedAction = "on_device"
        /// The phrase rules (KeywordRequestParser).
        case phraseRules = "phrase_rules"
        /// A saved place or station name on its own (ShortAnswerParser).
        case shortAnswer = "short_answer"
        /// Apple's on-device model: it understood the request, or found the
        /// place or station the other steps couldn't.
        case appleIntelligence = "apple_intelligence"
        /// The n8n backend.
        case server
    }

    var text: String
    /// The station the answer recommends, for directions. `nil` for
    /// answers that aren't about one station (citywide totals, server replies).
    var station: DockStation? = nil
    /// The full (or closed) dock the rider would otherwise have gone to,
    /// when the answer steers them away from one. Counts toward savings.
    var avoided: AvoidedDock? = nil
    var source: Source = .onDevice
    private(set) var answeredBy: Step = .fixedAction

    /// Sets `answeredBy`, and `source` to match.
    mutating func markAnswered(by step: Step) {
        answeredBy = step
        switch step {
        case .fixedAction, .phraseRules, .shortAnswer: source = .onDevice
        case .appleIntelligence: source = .onDeviceModel
        case .server: source = .server
        }
    }
}

// MARK: - Nearest dock to the rider

nonisolated struct DockSearchResult: Sendable, Equatable {
    let station: DockStation
    /// True when the user granted only approximate location, so the
    /// "nearest" station may not actually be the closest one.
    let locationIsApproximate: Bool
    /// The nearest station, when it's full and this answer skips it.
    var avoided: AvoidedDock? = nil

    /// "West 15th and 6th has 53 docks open, right there."
    var summary: String {
        var sentence = "\(station.spokenName) has \(Speech.docksOpen(station.availableDocks)), \(Speech.distance(station.straightLineDistance))."
        if locationIsApproximate {
            sentence += " Your location is approximate, so a closer dock may exist."
        }
        return sentence
    }

    var answer: DockAnswer { DockAnswer(text: summary, station: station, avoided: avoided) }
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
    /// With no usual dock: the station nearest the destination, when it's
    /// full and `selected` skips it.
    var skippedNearest: AvoidedDock? = nil

    var usesUsualDock: Bool { usualDock != nil && usualDockProblem == nil }

    /// The dock the rider would have gone to without Dock Finder: their
    /// usual one, or the nearest one, when it couldn't take a bike.
    var avoided: AvoidedDock? {
        guard selected != nil else { return nil }
        if let usualDock, let usualDockProblem {
            return AvoidedDock(usualDock, problem: usualDockProblem)
        }
        return skippedNearest
    }

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

    var answer: DockAnswer { DockAnswer(text: summary, station: selected, avoided: avoided) }
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

    /// The checked station, when it can't take a bike and there's an alternative.
    var avoided: AvoidedDock? {
        guard let problem, alternative != nil else { return nil }
        return AvoidedDock(station, problem: problem)
    }

    var answer: DockAnswer {
        let target = problem == nil
            ? DockStation(snapshot: station, distance: 0)
            : alternative
        return DockAnswer(text: summary, station: target, avoided: avoided)
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
