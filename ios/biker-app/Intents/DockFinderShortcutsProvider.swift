//
//  DockFinderShortcutsProvider.swift
//  Dock Finder
//
//  App Shortcuts are registered with the system automatically at install
//  time; nothing in the app needs to "enable" them. Phrases that mention a
//  saved place or a station are refreshed whenever those lists change.
//

import AppIntents

struct DockFinderShortcutsProvider: AppShortcutsProvider {
    /// Every phrase is "Ask Dock Finder to/for/if/how …" and says the whole
    /// request in one go. There's deliberately no bare "Ask Dock Finder":
    /// Siri could match it on the shared opening and drop the rest.
    ///
    /// **Never reorder or remove these; only append.** iOS remembers which
    /// phrase belongs to which position in this list and doesn't always
    /// re-read it when the app is updated, so reordering once made "start a
    /// ride" run Find Dock. If the list ever has to change shape, also bump
    /// `CURRENT_PROJECT_VERSION` in `Config/DockFinder.xcconfig`, which makes
    /// iOS re-read it.
    ///
    /// Siri matches phrases loosely, so keep each action's wording clearly
    /// different from the others' (only Find Dock may say "find a dock"
    /// without a saved place after it). Siri can only fill a blank from a
    /// list the app gives it (saved places, stations); free text such as an
    /// address can't be part of a phrase, so those actions ask for it.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Ask \(.applicationName) to start a ride to \(\.$place)",
                "Ask \(.applicationName) to start riding to \(\.$place)",
                "Ask \(.applicationName) to begin a ride to \(\.$place)",
                "Ask \(.applicationName) to start a ride",
                "Ask \(.applicationName) to begin a ride",
                "Ask \(.applicationName) to start riding",
            ],
            shortTitle: "Start Ride",
            systemImageName: "figure.outdoor.cycle"
        )
        AppShortcut(
            intent: EndRideIntent(),
            phrases: [
                "Ask \(.applicationName) to end my ride",
                "Ask \(.applicationName) to cancel my ride",
                "Ask \(.applicationName) to stop my ride",
            ],
            shortTitle: "End Ride",
            systemImageName: "flag.checkered"
        )
        AppShortcut(
            intent: FindDockIntent(),
            phrases: [
                "Ask \(.applicationName) to find a dock",
                "Ask \(.applicationName) to find me a dock",
                "Ask \(.applicationName) to find a dock near me",
                "Ask \(.applicationName) to find an open dock",
                "Ask \(.applicationName) to find the nearest dock",
                "Ask \(.applicationName) for a dock",
                "Ask \(.applicationName) for the nearest dock",
            ],
            shortTitle: "Find Dock",
            systemImageName: "bicycle"
        )
        AppShortcut(
            intent: FindDockNearSavedPlaceIntent(),
            phrases: [
                "Ask \(.applicationName) to check my \(\.$place) dock",
                "Ask \(.applicationName) to find a dock near \(\.$place)",
                "Ask \(.applicationName) to find a dock at \(\.$place)",
                "Ask \(.applicationName) for a dock near \(\.$place)",
            ],
            shortTitle: "Dock Near Saved Place",
            systemImageName: "star"
        )
        AppShortcut(
            intent: FindDockNearPlaceIntent(),
            phrases: [
                "Ask \(.applicationName) to find a dock somewhere else",
                "Ask \(.applicationName) for a dock somewhere else",
            ],
            shortTitle: "Dock Near a Place",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: CheckStationIntent(),
            phrases: [
                "Ask \(.applicationName) to check \(\.$station)",
                "Ask \(.applicationName) if \(\.$station) is full",
                "Ask \(.applicationName) about \(\.$station)",
                "Ask \(.applicationName) to check a station",
                "Ask \(.applicationName) if a station is full",
            ],
            shortTitle: "Check Station",
            systemImageName: "parkingsign.circle"
        )
        AppShortcut(
            intent: CitywideStatusIntent(),
            phrases: [
                "Ask \(.applicationName) for Citi Bike status",
                "Ask \(.applicationName) how many bikes are out",
                "Ask \(.applicationName) to check Citi Bike citywide",
            ],
            shortTitle: "Citywide Status",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: DirectMeIntent(),
            phrases: [
                "Ask \(.applicationName) to direct me",
                "Ask \(.applicationName) to direct me there",
                "Ask \(.applicationName) to take me there",
                "Ask \(.applicationName) to guide me to a dock",
                "Ask \(.applicationName) for directions",
            ],
            shortTitle: "Direct Me",
            systemImageName: "location.north.line"
        )
        AppShortcut(
            intent: StopDirectionsIntent(),
            phrases: [
                "Ask \(.applicationName) to stop directions",
                "Ask \(.applicationName) to cancel directions",
                "Ask \(.applicationName) to stop guiding me",
            ],
            shortTitle: "Stop Directions",
            systemImageName: "location.slash"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
