//
//  FindDockIntent.swift
//  Dock Finder
//
//  Every intent runs in the background and answers in one sentence: Siri
//  speaks it, and Shortcuts gets it as text (e.g. for Speak Text in an
//  arrival automation).
//

import AppIntents

typealias SpokenAnswerResult = IntentResult & ReturnsValue<String> & ProvidesDialog

extension DockAnswer {
    var intentResult: some SpokenAnswerResult {
        .result(value: text, dialog: "\(text)")
    }
}

struct FindDockIntent: AppIntent {
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
        try await DockFinderService.live.findNearestDock().answer.intentResult
    }
}

struct FindDockNearSavedPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Dock Near Saved Place"
    static let description = IntentDescription(
        "Checks your usual dock at a saved place, or finds the nearest dock there with room. Use it in an Arrive automation for a heads-up before you get there."
    )
    static let supportedModes: IntentModes = .background

    /// Optional on purpose. With a required saved-place parameter, Siri
    /// re-asks "Which place?" forever whenever it can't match the answer to
    /// a saved place (or there are none). The app answers instead.
    @Parameter(title: "Place")
    var place: SavedPlaceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Find a dock near \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        guard let place else {
            return DockAnswer(text: Self.whichPlaceHelp(SavedPlacesStore.shared.places)).intentResult
        }
        guard let saved = SavedPlacesStore.shared.place(id: place.id) else {
            throw DockFinderError.savedPlaceNotFound
        }
        return try await DockFinderService.live
            .findDock(for: saved)
            .answer.intentResult
    }
}

extension FindDockNearSavedPlaceIntent {
    static func whichPlaceHelp(_ places: [SavedPlace]) -> String {
        guard let first = places.first else {
            return "You don't have any saved places yet. Add one in Dock Finder."
        }
        let names = places.map(\.name).formatted(.list(type: .and))
        return "Your saved places are \(names). Say, for example, check my \(first.name.lowercased()) dock with Dock Finder."
    }
}

struct FindDockNearPlaceIntent: AppIntent {
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
        let router = AssistantRouter.live()
        return try await router.handle(.place(place)).intentResult
    }
}

struct CheckStationIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Station"
    static let description = IntentDescription(
        "Says whether a Citi Bike station has open docks, and where to go instead if it doesn't."
    )
    static let supportedModes: IntentModes = .background

    /// Plain text rather than a station entity, so Siri accepts whatever
    /// the rider says once and the app does the fuzzy matching. An entity
    /// parameter makes Siri re-ask when it can't resolve the answer.
    @Parameter(title: "Station", requestValueDialog: "Which station?")
    var station: String

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$station)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live()
            .handle(.station(KeywordRequestParser.normalize(station)))
            .intentResult
    }
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

/// The main Siri flow: "Hey Siri, start a ride with Dock Finder" → "Where
/// are you heading?" → "school" / "Union Square". Siri only has to match
/// that one phrase; the destination reaches the app as plain text, so Siri
/// can't mistake it for a Maps search.
struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Ride"
    static let description = IntentDescription(
        "Asks where you're heading, then tells you where to dock when you're close. The destination can be a saved place or anywhere Apple Maps finds. Works with your phone locked when Dock Finder has Always location access."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Destination", requestValueDialog: "Where are you heading?")
    var destination: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start a ride to \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live().handle(.startRide(destination)).intentResult
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

/// "Hey Siri, ask Dock Finder" → "What do you need?" → anything in your own
/// words: a station check, citywide totals, a usual-dock setting, or a
/// question only the server can answer. Rides and the nearest dock have
/// their own one-step phrases.
struct AskDockFinderIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Dock Finder"
    static let description = IntentDescription(
        "Ask anything in your own words, like whether a station is full or how many bikes are out. Dock Finder answers on your iPhone when it can, and asks the Dock Finder server otherwise."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Request", requestValueDialog: "What do you need?")
    var request: String

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live().answer(request).intentResult
    }
}
