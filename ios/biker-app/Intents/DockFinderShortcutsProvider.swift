//
//  DockFinderShortcutsProvider.swift
//  Dock Finder
//
//  App Shortcuts are registered with the system automatically at install
//  time; nothing in the app needs to "enable" them. Phrases that mention a
//  saved place are refreshed whenever saved places change.
//

import AppIntents

struct DockFinderShortcutsProvider: AppShortcutsProvider {
    /// The first shortcut is the one to teach riders: a single short phrase,
    /// then Siri asks for the details. The rest are one-step alternatives.
    ///
    /// Only Find Dock may use phrases that start with "find a dock". Siri
    /// matches phrases loosely, so any other "find a dock near/at …" phrase
    /// can win instead and ask a follow-up question, which turns a one-step
    /// request into a conversation. Destination requests go through "ask
    /// Dock Finder" instead.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskDockFinderIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Ask Dock Finder",
            systemImageName: "bicycle.circle"
        )
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Start a ride with \(.applicationName)",
                "Begin a ride with \(.applicationName)",
            ],
            shortTitle: "Start Ride",
            systemImageName: "figure.outdoor.cycle"
        )
        AppShortcut(
            intent: EndRideIntent(),
            phrases: [
                "End my ride with \(.applicationName)",
                "Cancel my ride with \(.applicationName)",
            ],
            shortTitle: "End Ride",
            systemImageName: "flag.checkered"
        )
        AppShortcut(
            intent: FindDockIntent(),
            phrases: [
                "Find a dock with \(.applicationName)",
                "Find me a dock with \(.applicationName)",
                "Find a dock in \(.applicationName)",
                "Find an available dock with \(.applicationName)",
                "Find an open dock with \(.applicationName)",
                "Find the nearest dock with \(.applicationName)",
                "Find a dock near me with \(.applicationName)",
                "Nearest dock in \(.applicationName)",
            ],
            shortTitle: "Find Dock",
            systemImageName: "bicycle"
        )
        // Find Dock Near a Place has no Siri phrase on purpose (see above);
        // it's still an action in the Shortcuts app.
        AppShortcut(
            intent: FindDockNearSavedPlaceIntent(),
            phrases: [
                "Check my \(\.$place) dock with \(.applicationName)",
            ],
            shortTitle: "Dock Near Saved Place",
            systemImageName: "star"
        )
        AppShortcut(
            intent: CheckStationIntent(),
            phrases: [
                "Check a station with \(.applicationName)",
                "Is a station full in \(.applicationName)",
            ],
            shortTitle: "Check Station",
            systemImageName: "parkingsign.circle"
        )
        AppShortcut(
            intent: CitywideStatusIntent(),
            phrases: [
                "Citi Bike status in \(.applicationName)",
                "Check Citi Bike citywide with \(.applicationName)",
            ],
            shortTitle: "Citywide Status",
            systemImageName: "chart.bar"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
