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
            intent: FindDockIntent(),
            phrases: [
                "Find a dock with \(.applicationName)",
                "Find an available dock with \(.applicationName)",
                "Find a dock in \(.applicationName)",
                "Find a dock near me with \(.applicationName)",
            ],
            shortTitle: "Find Dock",
            systemImageName: "bicycle"
        )
        AppShortcut(
            intent: FindDockNearSavedPlaceIntent(),
            phrases: [
                "Find a dock near \(\.$place) with \(.applicationName)",
                "Check my \(\.$place) dock with \(.applicationName)",
                "Find a dock at \(\.$place) with \(.applicationName)",
            ],
            shortTitle: "Dock Near Saved Place",
            systemImageName: "star"
        )
        AppShortcut(
            intent: FindDockNearPlaceIntent(),
            phrases: [
                "Find a dock near a place with \(.applicationName)",
                "Find a dock at my destination with \(.applicationName)",
            ],
            shortTitle: "Dock Near a Place",
            systemImageName: "mappin.and.ellipse"
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
