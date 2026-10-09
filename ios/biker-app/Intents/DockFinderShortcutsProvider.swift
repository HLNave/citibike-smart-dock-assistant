//
//  DockFinderShortcutsProvider.swift
//  Dock Finder
//
//  App Shortcuts are registered with the system automatically at install
//  time; nothing in the app needs to "enable" them.
//

import AppIntents

struct DockFinderShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindDockIntent(),
            phrases: [
                "Find a dock with \(.applicationName)",
                "Find an available dock with \(.applicationName)",
                "Find a dock in \(.applicationName)",
            ],
            shortTitle: "Find Dock",
            systemImageName: "bicycle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
