//
//  PlacesBackupTests.swift
//  DockFinderTests
//
//  Saved places come back after the app is deleted and reinstalled.
//

import Foundation
import Testing
@testable import DockFinder

/// Stands in for the keychain, which survives an app delete.
final class MemoryBackup: PlacesBackup, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    init(_ data: Data? = nil) { self.data = data }

    func read() -> Data? { lock.withLock { data } }
    func write(_ data: Data) { lock.withLock { self.data = data } }
}

@MainActor
struct PlacesBackupTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID())")!
    }

    @Test func placesComeBackAfterReinstall() {
        let backup = MemoryBackup()
        let before = SavedPlacesStore(defaults: freshDefaults(), backup: backup, onChange: {})
        before.add(SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, usualStationID: "s1", usualStationName: "Mercer St & Bleecker St"))
        before.add(SavedPlace(name: "Home", latitude: 40.6861, longitude: -73.9906))

        // Deleting the app wipes its defaults; the backup survives.
        var changes = 0
        let after = SavedPlacesStore(defaults: freshDefaults(), backup: backup, onChange: { changes += 1 })
        #expect(after.places.map(\.name) == ["School", "Home"])
        #expect(after.places.first?.usualStationName == "Mercer St & Bleecker St")
        #expect(changes == 1, "Siri phrases should be refreshed for the restored places")
    }

    @Test func existingPlacesWinOverTheBackup() {
        let defaults = freshDefaults()
        SavedPlacesStore(defaults: defaults, onChange: {}).add(SavedPlace(name: "Work", latitude: 0, longitude: 0))
        let olderBackup = MemoryBackup(try? JSONEncoder().encode([SavedPlace(name: "School", latitude: 0, longitude: 0)]))
        #expect(SavedPlacesStore(defaults: defaults, backup: olderBackup, onChange: {}).places.map(\.name) == ["Work"])
    }

    @Test func deletingEveryPlaceStaysDeletedAfterReinstall() {
        let backup = MemoryBackup()
        let store = SavedPlacesStore(defaults: freshDefaults(), backup: backup, onChange: {})
        let place = SavedPlace(name: "Gym", latitude: 0, longitude: 0)
        store.add(place)
        store.remove(id: place.id)
        #expect(SavedPlacesStore(defaults: freshDefaults(), backup: backup, onChange: {}).places.isEmpty)
    }
}
