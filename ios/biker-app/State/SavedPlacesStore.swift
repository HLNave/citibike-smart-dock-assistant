//
//  SavedPlacesStore.swift
//  Dock Finder
//
//  The rider's regular destinations (school, work, home…) and the usual
//  dock at each one. Stored on this device only. Siri phrases like
//  "Find a dock near school with Dock Finder" are built from this list.
//

import AppIntents
import Foundation
import Observation

nonisolated struct SavedPlace: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var usualStationID: String?
    var usualStationName: String?

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        usualStationID: String? = nil,
        usualStationName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.usualStationID = usualStationID
        self.usualStationName = usualStationName
    }

    var destination: Destination {
        Destination(name: name, latitude: latitude, longitude: longitude, address: address)
    }

    /// True if what the rider said refers to this place: "school", "my school", "School".
    func matches(_ spoken: String) -> Bool {
        let normalized = spoken.lowercased()
            .replacingOccurrences(of: "my ", with: "")
            .replacingOccurrences(of: "the ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return normalized == name.lowercased()
    }
}

@Observable
final class SavedPlacesStore {
    static let shared = SavedPlacesStore()
    nonisolated static let storageKey = "savedPlaces"

    private let defaults: UserDefaults
    private let onChange: () -> Void

    private(set) var places: [SavedPlace]

    init(defaults: UserDefaults = .standard, onChange: @escaping () -> Void = SavedPlacesStore.refreshSiriPhrases) {
        self.defaults = defaults
        self.onChange = onChange
        places = Self.load(from: defaults)
    }

    func place(id: UUID) -> SavedPlace? {
        places.first { $0.id == id }
    }

    /// The saved place the rider means by "school" / "my school", if any.
    func place(matching spoken: String) -> SavedPlace? {
        places.first { $0.matches(spoken) }
    }

    func add(_ place: SavedPlace) {
        places.append(place)
        save()
    }

    func update(_ place: SavedPlace) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index] = place
        save()
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            places.remove(at: index)
        }
        save()
    }

    func setUsualDock(stationID: String?, stationName: String?, for placeID: UUID) {
        guard var place = place(id: placeID) else { return }
        place.usualStationID = stationID
        place.usualStationName = stationName
        update(place)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: Self.storageKey)
        }
        onChange()
    }

    nonisolated static func load(from defaults: UserDefaults) -> [SavedPlace] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([SavedPlace].self, from: data)) ?? []
    }

    /// Tells Siri the saved-place names changed, so phrases that mention
    /// them ("…near school…") start working without reinstalling.
    nonisolated static func refreshSiriPhrases() {
        DockFinderShortcutsProvider.updateAppShortcutParameters()
    }
}
