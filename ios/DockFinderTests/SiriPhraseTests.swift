//
//  SiriPhraseTests.swift
//  DockFinderTests
//
//  Guards the Siri phrase list: every phrase is "Ask Dock Finder …", and
//  iOS remembers which phrase belongs to which position in
//  DockFinderShortcutsProvider and doesn't always re-read it on update;
//  reordering once made "start a ride" run Find Dock.
//

import Foundation
import Testing
@testable import DockFinder

struct SiriPhraseTests {
    /// The order phones already know. Append new shortcuts after these.
    static let knownOrder = [
        "StartRideIntent",
        "EndRideIntent",
        "FindDockIntent",
        "FindDockNearSavedPlaceIntent",
        "FindDockNearPlaceIntent",
        "CheckStationIntent",
        "CitywideStatusIntent",
        "DirectMeIntent",
        "StopDirectionsIntent",
        "AskDockFinderIntent",
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

    @Test func everyPhraseIsAskDockFinderAndARequest() throws {
        let phrases = try shortcuts().flatMap(\.phrases)
        #expect(!phrases.isEmpty)
        for phrase in phrases {
            #expect(phrase.hasPrefix("Ask ${applicationName} "), "\(phrase) should start with \"Ask Dock Finder\"")
        }
        // A bare "Ask Dock Finder" could win on the shared opening and drop the request.
        #expect(!phrases.contains("Ask ${applicationName}"))
    }

    @Test func everyDockPhraseAlsoTakesDoc() throws {
        // Siri often hears "dock" as "doc".
        let phrases = Set(try shortcuts().flatMap(\.phrases))
        for phrase in phrases where phrase.contains("dock") {
            let doc = phrase.replacingOccurrences(of: "dock", with: "doc")
            #expect(phrases.contains(doc), "Missing \"\(doc)\"")
        }
    }

    @Test func onlyFindDockFindsADockWithoutAPlace() throws {
        let owners = try shortcuts()
            .filter { $0.phrases.contains { [" to find a dock", " to find a doc"].contains(where: $0.lowercased().hasSuffix) } }
            .map(\.intent)
        #expect(owners == ["FindDockIntent"], "Another plain \"find a dock\" phrase can steal Find Dock's requests.")
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
        #expect(FindDockNearSavedPlaceIntent.whichPlaceHelp(places) == "Your saved places are School and Work. Say, for example, ask Dock Finder to check my school dock.")
    }
}

@MainActor
struct RecentStationsTests {
    @Test func newestFirstWithoutRepeatsAndKept() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let recent = RecentStations(defaults: defaults)
        recent.add(id: "a", name: "Mercer St & Bleecker St")
        recent.add(id: "b", name: "Court St & State St")
        recent.add(id: "a", name: "Mercer St & Bleecker St")
        #expect(recent.stations.map(\.id) == ["a", "b"])
        #expect(RecentStations(defaults: defaults).stations.map(\.id) == ["a", "b"])
    }

    @Test func onlyTheLatestAreKept() {
        let recent = RecentStations(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        for index in 0..<(RecentStations.limit + 5) {
            recent.add(id: "\(index)", name: "Station \(index)")
        }
        #expect(recent.stations.count == RecentStations.limit)
        #expect(recent.stations.first?.id == "\(RecentStations.limit + 4)")
    }
}
