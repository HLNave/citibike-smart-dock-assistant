//
//  DirectionsPreference.swift
//  Dock Finder
//
//  "When Siri finds a dock": start turn-by-turn directions straight away,
//  ask first (the default), or never offer them. Also decides whether a
//  ride started with Siri guides the rider to the dock, so riders who
//  always (or never) want directions aren't asked every time.
//

import Foundation

nonisolated enum DirectionsPreference: String, Sendable, CaseIterable, Identifiable {
    /// Start directions as soon as an answer names a dock.
    case always
    /// "Want me to direct you there?"
    case ask
    /// Just say where the dock is.
    case never

    static let key = "directionsPreference"
    /// The Start a Ride screen's "Guide me to the dock" switch, remembered
    /// between rides (the key it has always used).
    static let rideSwitchKey = "guideRidesToDock"

    var id: String { rawValue }

    static func current(in defaults: UserDefaults = .standard) -> DirectionsPreference {
        defaults.string(forKey: key).flatMap(DirectionsPreference.init(rawValue:)) ?? .ask
    }

    static func set(_ choice: DirectionsPreference, in defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: key)
    }

    var title: String {
        switch self {
        case .always: "Start Right Away"
        case .ask: "Ask Me"
        case .never: "Don't Offer"
        }
    }

    var explanation: String {
        switch self {
        case .always: "Siri starts turn-by-turn directions as soon as it names a dock."
        case .ask: "Siri asks “Want me to direct you there?”"
        case .never: "Siri just tells you where to dock."
        }
    }

    /// Whether a new ride guides the rider to the dock, decided without
    /// asking. `nil` means ask.
    var guidesNewRides: Bool? {
        switch self {
        case .always: true
        case .never: false
        case .ask: nil
        }
    }

    /// Where the Start a Ride screen's switch starts: set by this
    /// preference, or with Ask Me, as it was left last time (on at first).
    static func rideSwitchDefault(in defaults: UserDefaults = .standard) -> Bool {
        current(in: defaults).guidesNewRides ?? (defaults.object(forKey: rideSwitchKey) as? Bool ?? true)
    }

    /// Only Ask Me remembers the switch; with the other two, flipping it
    /// changes one ride.
    static func rememberRideSwitch(_ isOn: Bool, in defaults: UserDefaults = .standard) {
        guard current(in: defaults) == .ask else { return }
        defaults.set(isOn, forKey: rideSwitchKey)
    }
}

/// What Siri does after speaking an answer. Worked out here, rather than
/// inside the intent, so it can be tested without Siri.
nonisolated enum SiriFollowUp: Equatable, Sendable {
    /// Nothing more to say.
    case none
    /// "Want me to guide you to the dock when you're close?"
    case askToGuideRide
    /// Set whether the new ride guides to the dock, without asking.
    case guideRide(Bool)
    /// "Want me to direct you there?"
    case offerDirections(DockStation)
    /// Start directions without asking.
    case startDirections(DockStation)

    /// - Parameters:
    ///   - startedRide: The answer started a new ride.
    ///   - guidingToStationID: The dock directions are already running to, if any.
    static func after(
        _ answer: DockAnswer,
        startedRide: Bool,
        guidingToStationID: String?,
        preference: DirectionsPreference
    ) -> SiriFollowUp {
        if startedRide {
            return preference.guidesNewRides.map(SiriFollowUp.guideRide) ?? .askToGuideRide
        }
        guard let station = answer.station, station.id != guidingToStationID else { return .none }
        switch preference {
        case .always: return .startDirections(station)
        case .ask: return .offerDirections(station)
        case .never: return .none
        }
    }
}
