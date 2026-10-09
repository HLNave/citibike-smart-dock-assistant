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

    @Parameter(title: "Place", requestValueDialog: "Which place?")
    var place: SavedPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Find a dock near \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        guard let saved = SavedPlacesStore.shared.place(id: place.id) else {
            throw DockFinderError.savedPlaceNotFound
        }
        return try await DockFinderService.live
            .findDock(for: saved)
            .answer.intentResult
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

    @Parameter(title: "Station", requestValueDialog: "Which station?")
    var station: StationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$station)")
    }

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await DockFinderService.live.checkStation(station.id).answer.intentResult
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

struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Ride"
    static let description = IntentDescription(
        "Watches your ride to a saved place or any destination, and tells you where to dock when you're close. Works with your phone locked when Dock Finder has Always location access."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Destination", requestValueDialog: "Where are you riding to?")
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

/// The main Siri entry point: "Hey Siri, ask Dock Finder", then Siri asks
/// what you need. ("Run Dock Finder" can't be used: Siri treats "run" or
/// "open" plus an app's name as "open the app", which needs an unlock.) Siri only has to recognize that one short phrase; the
/// answer to the follow-up comes to the app as plain text, so Siri can't
/// mistake it for a Maps search ("dock" heard as "doc" → doctors nearby).
struct AskDockFinderIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Dock Finder"
    static let description = IntentDescription(
        "Asks where you're headed, then answers in one sentence: a dock near a place or saved place, a station's status, or the nearest dock to you. Dock Finder answers on your iPhone when it can, and asks the Dock Finder server otherwise."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Request", requestValueDialog: "Where are you headed, or which station?")
    var request: String

    @MainActor
    func perform() async throws -> some SpokenAnswerResult {
        try await AssistantRouter.live().answer(request).intentResult
    }
}
