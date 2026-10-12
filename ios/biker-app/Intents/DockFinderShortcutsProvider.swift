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
    /// **Never reorder or remove these; only append.** iOS remembers which
    /// phrase belongs to which position in this list and doesn't always
    /// re-read it when the app is updated, so reordering made "start a ride"
    /// run Find Dock and "find a dock" run the saved-place shortcut. If the
    /// list ever has to change shape, also bump `CURRENT_PROJECT_VERSION` in
    /// `Config/DockFinder.xcconfig`, which makes iOS re-read it.
    ///
    /// Only Find Dock may use phrases that start with "find a dock". Siri
    /// matches phrases loosely, so any other "find a dock near/at …" phrase
    /// can win instead and ask a follow-up question. ("Run/start Dock
    /// Finder" can't be used at all: Siri treats a launch verb plus the
    /// app's name as "open the app", which needs an unlock.)
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskDockFinderIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Ask Dock Finder",
            systemImageName: "bubble.left"
        )
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Start a ride with \(.applicationName)",
                "Begin a ride with \(.applicationName)",
                "Start riding with \(.applicationName)",
                "New ride with \(.applicationName)",
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
