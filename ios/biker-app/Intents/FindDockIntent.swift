//
//  FindDockIntent.swift
//  Dock Finder
//
//  Every intent runs in the background and answers in one sentence: Siri
//  speaks it, and Shortcuts gets it as text (e.g. for Speak Text in an
//  arrival automation).
//
//  Answers that name a dock end with "Want me to direct you there?", and
//  a new ride asks "Want me to guide you to the dock when you're close?".
//  Siri is already in the conversation, so the rider can answer by voice
//  with the phone locked. Intents that can start guidance or a ride are
//  LiveActivityIntents, which lets them start the Lock Screen activity
//  from the background.
//

import AppIntents

typealias SpokenAnswerResult = IntentResult & ReturnsValue<String> & ProvidesDialog

/// Every intent result goes through here, so all of an intent's return
/// paths have the same type. `value` is what Shortcuts receives.
func spokenResult(_ value: String, dialog: String? = nil) -> some SpokenAnswerResult {
    .result(value: value, dialog: "\(dialog ?? value)")
}

extension DockAnswer {
    var intentResult: some SpokenAnswerResult {
        spokenResult(text)
    }
}

extension AppIntent {
    /// Speaks `answer`, then follows up:
    /// - When `answer` started a ride (it's not the ride from before), asks
    ///   whether to guide the rider to the dock on arrival.
    /// - When it names a dock, asks "Want me to direct you there?" and, on
    ///   yes, confirms and starts turn-by-turn guidance in the app's voice.
    @MainActor
    func reply(
        with answer: DockAnswer,
        rideBefore: Ride? = nil,
        checksForNewRide: Bool = false
    ) async throws -> some SpokenAnswerResult {
        let guidance = GuidanceSession.shared
        let here = LocationService.shared.lastKnownLocation
        Metrics.shared.log(
            "siri_answer",
            station: answer.station?.name,
            avoidedStation: answer.avoided?.name,
            location: here,
            details: ["intent": String(describing: Self.self), "answer": answer.text]
        )
        SavingsStore.shared.record(answer, from: here, context: "siri")
        if answer.station != nil {
            // Dock information by voice: the rider didn't take out their phone.
            SavingsStore.shared.recordHandsFree(context: "siri")
        }

        if checksForNewRide, let ride = RideTracker.shared.currentRide, ride != rideBefore {
            do {
                try await requestConfirmation(
                    conditions: [],
                    actionName: .go,
                    dialog: "\(answer.text) \(GuidanceSession.rideQuestion)"
                )
            } catch {
                return spokenResult(answer.text, dialog: "Okay. I'll just tell you where to dock.")
            }
            RideTracker.shared.setGuidesToDock(true)
            return spokenResult(answer.text, dialog: "Okay. When you're close, I'll guide you to the dock.")
        }

        guard let station = answer.station else { return spokenResult(answer.text) }
        guidance.offer(station)
        guard guidance.station?.id != station.id else { return spokenResult(answer.text) }
        do {
            try await requestConfirmation(
                conditions: [],
                actionName: .go,
                dialog: "\(answer.text) \(GuidanceSession.offerQuestion)"
            )
        } catch {
            // "No", or Siri couldn't ask. The answer was already spoken with
            // the question, so don't repeat it.
            return spokenResult(answer.text, dialog: "Okay.")
        }
        // Siri only confirms; the app's voice gives the directions once Siri
        // has finished, so the two don't talk over each other.
        let siriLine = guidance.siriConfirmation(for: station)
        let reply = try await guidance.start(to: station, siriWillSay: siriLine)
        return spokenResult(guidance.isActive ? siriLine : reply)
    }
}

struct FindDockIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Find Dock"
    static let description = IntentDescription(
        "Finds the nearest Citi Bike station with room to return your bike."
    )

    /// Run without bringing the app to the foreground. Everything this
    /// intent needs (location + network) is available in the background
    /// while the intent is running.
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        // Errors conform to CustomLocalizedStringResourceConvertible, so Siri
        // speaks their message when they propagate.
        let answer = try await DockFinderService.live.findNearestDock().answer
        return try await reply(with: answer)
    }
}

struct FindDockNearSavedPlaceIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Find Dock Near Saved Place"
    static let description = IntentDescription(
        "Checks your usual dock at a saved place, or finds the nearest dock there with room."
    )
    static let supportedModes: IntentModes = .background

    /// Optional on purpose. With a required saved-place parameter, Siri
    /// re-asks "Which place?" forever whenever it can't match the answer to
    /// a saved place (or there are none). The app answers instead.
    @Parameter(title: "Place")
    var place: SavedPlaceEntity?

    /// Asked for, once, when Siri ran the phrase without catching which
    /// place was meant. Plain text, matched by the app, so whatever the
    /// rider says is accepted and nothing is re-asked.
    @Parameter(title: "Place Name")
    var placeName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Find a dock near \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        let store = SavedPlacesStore.shared
        let saved: SavedPlace
        if let place {
            guard let match = store.place(id: place.id) else {
                throw DockFinderError.savedPlaceNotFound
            }
            saved = match
        } else if store.places.count == 1, let only = store.places.first {
            saved = only
        } else if !store.places.isEmpty {
            let names = store.places.map(\.name).formatted(.list(type: .or))
            let spoken: String? = try await $placeName.requestValue("Which place: \(names)?")
            guard let match = spoken.flatMap(store.place(matching:)) else {
                return try await reply(with: DockAnswer(text: Self.whichPlaceHelp(store.places)))
            }
            saved = match
        } else {
            return try await reply(with: DockAnswer(text: Self.whichPlaceHelp(store.places)))
        }
        let answer = try await DockFinderService.live.findDock(for: saved).answer
        return try await reply(with: answer)
    }
}

extension FindDockNearSavedPlaceIntent {
    static func whichPlaceHelp(_ places: [SavedPlace]) -> String {
        guard let first = places.first else {
            return "You don't have any saved places yet. Add one in Dock Finder."
        }
        let names = places.map(\.name).formatted(.list(type: .and))
        return "Your saved places are \(names). Say, for example, ask Dock Finder to check my \(first.name.lowercased()) dock."
    }
}

struct FindDockNearPlaceIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Find Dock Near a Place"
    static let description = IntentDescription(
        "Finds a dock with room near an address, landmark or neighborhood, like Union Square."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Place", requestValueDialog: "Where are you headed?")
    var place: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find a dock near \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        let answer = try await AssistantRouter.live().handle(.place(place))
        return try await reply(with: answer)
    }
}

struct CheckStationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check Station"
    static let description = IntentDescription(
        "Says whether a Citi Bike station has open docks, and where to go instead if it doesn't."
    )
    static let supportedModes: IntentModes = .background

    /// Filled straight from the phrase ("…check Mercer and Bleecker") for
    /// the stations Siri knows about (see `StationQuery.suggestedEntities`).
    /// Optional, so Siri never re-asks when it can't match a station.
    @Parameter(title: "Station")
    var station: StationEntity?

    /// Asked for when the phrase didn't name a station Siri knows. Plain
    /// text, so Siri accepts whatever the rider says once and the app does
    /// the fuzzy matching.
    @Parameter(title: "Station Name")
    var stationName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$station)") {
            \.$stationName
        }
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        let spoken: String
        if let station {
            spoken = station.name
        } else if let stationName, !stationName.isEmpty {
            spoken = stationName
        } else {
            spoken = try await $stationName.requestValue("Which station?")
        }
        guard !spoken.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try await reply(with: DockAnswer(text: Self.whichStationHelp))
        }
        let answer = try await AssistantRouter.live().handle(.station(KeywordRequestParser.normalize(spoken)))
        // A full station's answer names the alternative; the one asked about is `avoided`.
        if let id = answer.avoided?.id ?? answer.station?.id,
           let name = answer.avoided?.name ?? answer.station?.name {
            RecentStations.shared.add(id: id, name: name)
        }
        return try await reply(with: answer)
    }
}

extension CheckStationIntent {
    static let whichStationHelp = "Say which station, for example, ask Dock Finder to check Mercer and Bleecker."
}

struct CitywideStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Citywide Status"
    static let description = IntentDescription(
        "Totals for the whole Citi Bike system: bikes available, open docks, and full stations."
    )
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await DockFinderService.live.citywideSummary().answer.intentResult
    }
}

struct SetUsualDockIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Usual Dock"
    static let description = IntentDescription(
        "Remembers which station you normally use at a saved place."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Place", requestValueDialog: "For which place?")
    var place: SavedPlaceEntity

    @Parameter(title: "Station", requestValueDialog: "Which station?")
    var station: StationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$station) as my usual dock at \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        guard SavedPlacesStore.shared.place(id: place.id) != nil else {
            throw DockFinderError.savedPlaceNotFound
        }
        SavedPlacesStore.shared.setUsualDock(stationID: station.id, stationName: station.name, for: place.id)
        return DockAnswer(text: "Got it. \(Speech.stationName(station.name)) is your \(place.name) dock.").intentResult
    }
}

/// The main Siri flow: "Hey Siri, ask Dock Finder to start a ride to
/// school", in one go for a saved place. "…to start a ride" on its own asks
/// "Where are you heading?", and the answer (a saved place, landmark or
/// address) reaches the app as plain text, so Siri can't mistake it for a
/// Maps search.
struct StartRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Ride"
    static let description = IntentDescription(
        "Tells you where to dock when you're close to where you're heading. The destination can be a saved place, a landmark or an address. Works with your phone locked when Dock Finder has Always location access."
    )
    static let supportedModes: IntentModes = .background

    /// Filled straight from the phrase ("…start a ride to school"). Optional,
    /// so Siri never re-asks when it can't match a saved place.
    @Parameter(title: "Saved Place")
    var place: SavedPlaceEntity?

    @Parameter(title: "Destination")
    var destination: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a ride to \(\.$destination)") {
            \.$place
        }
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        let rideBefore = RideTracker.shared.currentRide
        let spoken: String
        if let place {
            spoken = place.name
        } else if let destination, !destination.isEmpty {
            spoken = destination
        } else {
            spoken = try await $destination.requestValue("Where are you heading?")
        }
        let answer = try await AssistantRouter.live().handle(.startRide(spoken))
        return try await reply(with: answer, rideBefore: rideBefore, checksForNewRide: true)
    }
}

struct EndRideIntent: AppIntent {
    static let title: LocalizedStringResource = "End Ride"
    static let description = IntentDescription("Stops watching your current ride.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live().handle(.endRide).intentResult
    }
}

/// "Hey Siri, ask Dock Finder to direct me": turn-by-turn guidance to the
/// dock Siri just mentioned, or to the nearest dock with room. Also the
/// fallback if a yes/no follow-up ever doesn't get through.
struct DirectMeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Direct Me to a Dock"
    static let description = IntentDescription(
        "Guides you turn by turn, through your headphones, to the dock Dock Finder just told you about, or to the nearest dock with room."
    )
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        let answer = try await AssistantRouter.live().handle(.directions)
        if GuidanceSession.shared.isActive {
            SavingsStore.shared.recordHandsFree(context: "directions")
        }
        return answer.intentResult
    }
}

struct StopDirectionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Directions"
    static let description = IntentDescription("Stops turn-by-turn guidance to a dock.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live().handle(.stopDirections).intentResult
    }
}
