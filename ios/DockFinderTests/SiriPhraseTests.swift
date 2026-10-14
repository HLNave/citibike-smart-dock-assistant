//
//  SiriPhraseTests.swift
//  DockFinderTests
//
//  Guards the Siri phrase list. iOS remembers which phrase belongs to which
//  position in DockFinderShortcutsProvider and doesn't always re-read it on
//  update; reordering once made "start a ride" run Find Dock and "find a
//  dock" ask "Which place?" forever.
//

import Foundation
import Testing
@testable import DockFinder

struct SiriPhraseTests {
    /// The order phones already know. Append new shortcuts after these.
    static let knownOrder = [
        "AskDockFinderIntent",
        "StartRideIntent",
        "EndRideIntent",
        "FindDockIntent",
        "FindDockNearSavedPlaceIntent",
        "CheckStationIntent",
        "CitywideStatusIntent",
        "StopDirectionsIntent",
        "DirectMeIntent",
    ]

    /// The App Shortcuts metadata Xcode extracts into the app bundle.
    private func shortcuts() throws -> [(intent: String, phrases: [String])] {
        let url = try #require(
            Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
            "App Intents metadata missing from the app bundle"
        )
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try #require(json["autoShortcuts"] as? [[String: Any]])
        return entries.map { entry in
            let templates = entry["phraseTemplates"] as? [[String: Any]] ?? []
            return (entry["actionIdentifier"] as? String ?? "", templates.compactMap { $0["key"] as? String })
        }
    }

    @Test func shortcutsAreOnlyEverAppended() throws {
        let order = try shortcuts().map(\.intent)
        #expect(
            Array(order.prefix(Self.knownOrder.count)) == Self.knownOrder,
            "Don't reorder or remove App Shortcuts; append new ones at the end and bump CURRENT_PROJECT_VERSION."
        )
    }

    @Test func onlyFindDockStartsWithFindADock() throws {
        let owners = try shortcuts()
            .filter { $0.phrases.contains { $0.lowercased().hasPrefix("find a dock") } }
            .map(\.intent)
        #expect(owners == ["FindDockIntent"], "Another \"find a dock…\" phrase can steal \"Find a dock with Dock Finder\".")
    }

    @Test func noPhraseIsJustALaunchVerb() throws {
        // "Run/open/start/launch Dock Finder" opens the app instead of running an action.
        let launchOnly = try shortcuts().flatMap(\.phrases).filter { phrase in
            ["run", "open", "start", "launch"].contains { phrase == "\($0.capitalized) ${applicationName}" }
        }
        #expect(launchOnly.isEmpty)
    }
}

@MainActor
struct SavedPlaceShortcutTests {
    @Test func missingPlaceIsAnsweredInsteadOfReasked() {
        #expect(FindDockNearSavedPlaceIntent.whichPlaceHelp([]) == "You don't have any saved places yet. Add one in Dock Finder.")
        let places = [
            SavedPlace(name: "School", latitude: 0, longitude: 0),
            SavedPlace(name: "Work", latitude: 0, longitude: 0),
        ]
        #expect(FindDockNearSavedPlaceIntent.whichPlaceHelp(places) == "Your saved places are School and Work. Say, for example, check my school dock with Dock Finder.")
    }
}
