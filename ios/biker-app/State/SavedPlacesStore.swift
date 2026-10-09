//
//  SavedPlacesStore.swift
//  Dock Finder
//
//  The rider's regular destinations (school, work, home…): what they call
//  each one, its usual and backup docks, and how early to warn them on a
//  ride. Stored on this device only. Siri phrases like "Find a dock near
//  school with Dock Finder" are built from this list.
//

import AppIntents
import CoreLocation
import Foundation
import Observation

nonisolated struct SavedPlace: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// How far out a ride announces the best dock, unless the place says otherwise.
    static let defaultAlertDistance: CLLocationDistance = 500
    static let alertDistanceOptions: [CLLocationDistance] = [300, 500, 800, 1_200]

    var id: UUID
    var name: String
    /// Other things the rider calls this place: "Stern", "class".
    var aliases: [String]
    var latitude: Double
    var longitude: Double
    var address: String?
    var usualStationID: String?
    var usualStationName: String?
    /// Tried when the usual dock is full, before any other station.
    var backupStationID: String?
    var backupStationName: String?
    var alertDistance: CLLocationDistance

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        usualStationID: String? = nil,
        usualStationName: String? = nil,
        backupStationID: String? = nil,
        backupStationName: String? = nil,
        alertDistance: CLLocationDistance = SavedPlace.defaultAlertDistance
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.usualStationID = usualStationID
        self.usualStationName = usualStationName
        self.backupStationID = backupStationID
        self.backupStationName = backupStationName
        self.alertDistance = alertDistance
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, latitude, longitude, address
        case usualStationID, usualStationName, backupStationID, backupStationName, alertDistance
    }

    /// Only the name and coordinates are required, so places saved by an
    /// older version of the app (or missing a newer field) still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        usualStationID = try container.decodeIfPresent(String.self, forKey: .usualStationID)
        usualStationName = try container.decodeIfPresent(String.self, forKey: .usualStationName)
        backupStationID = try container.decodeIfPresent(String.self, forKey: .backupStationID)
        backupStationName = try container.decodeIfPresent(String.self, forKey: .backupStationName)
        let distance = try container.decodeIfPresent(Double.self, forKey: .alertDistance) ?? Self.defaultAlertDistance
        alertDistance = distance > 0 ? distance : Self.defaultAlertDistance
    }

    var destination: Destination {
        Destination(name: name, latitude: latitude, longitude: longitude, address: address)
    }

    var location: CLLocation { destination.location }

    /// Every name the rider might use for this place.
    var spokenNames: [String] { [name] + aliases }

    /// True if what the rider said refers to this place: "school", "my
    /// school", "the School", "my school dock", or one typo off ("shcool").
    func matches(_ spoken: String) -> Bool {
        let said = Self.normalizedName(spoken)
        guard !said.isEmpty else { return false }
        return spokenNames.map(Self.normalizedName).contains { candidate in
            candidate == said
                || (said.count >= 5 && candidate.count >= 5 && StationNameMatcher.editDistance(said, candidate) <= 1)
        }
    }

    /// "My School Dock!" → "school".
    static func normalizedName(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s", with: "")
        let cleaned = String(lowered.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words: [String] = cleaned.split(separator: " ").map { String($0) }
        while let first = words.first, ["my", "the", "our", "usual"].contains(first) {
            words.removeFirst()
        }
        while let last = words.last, ["dock", "docks", "station", "place"].contains(last), words.count > 1 {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}

@Observable
final class SavedPlacesStore {
    static let shared = SavedPlacesStore()
    nonisolated static let storageKey = "savedPlaces"
    /// Unreadable data is copied here instead of being overwritten, so a bad
    /// update can't silently erase the rider's places.
    nonisolated static let unreadableBackupKey = "savedPlaces.unreadable"

    enum ValidationError: Error, Equatable, CustomLocalizedStringResourceConvertible {
        case emptyName
        /// `name` is already what the rider calls `place`.
        case nameTaken(name: String, place: String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .emptyName: "Give this place a name."
            case .nameTaken(let name, let place): "“\(name)” is already used for \(place). Pick a different name."
            }
        }
    }

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
        let said = SavedPlace.normalizedName(spoken)
        // Prefer an exact name or alias over a one-typo match.
        return places.first { $0.spokenNames.map(SavedPlace.normalizedName).contains(said) }
            ?? places.first { $0.matches(spoken) }
    }

    /// Checks a name and its aliases against every other place, so Siri
    /// never has two places answering to the same word.
    func validate(name: String, aliases: [String] = [], excluding id: UUID? = nil) -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SavedPlace.normalizedName(trimmed).isEmpty else { return .emptyName }
        let others = places.filter { $0.id != id }
        for candidate in [trimmed] + aliases {
            let normalized = SavedPlace.normalizedName(candidate)
            guard !normalized.isEmpty else { continue }
            if let clash = others.first(where: { $0.spokenNames.map(SavedPlace.normalizedName).contains(normalized) }) {
                return .nameTaken(name: candidate, place: clash.name)
            }
        }
        return nil
    }

    func add(_ place: SavedPlace) {
        places.append(Self.cleaned(place))
        save()
    }

    func update(_ place: SavedPlace) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index] = Self.cleaned(place)
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

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { places[$0] }
        for index in source.sorted(by: >) {
            places.remove(at: index)
        }
        let insertAt = destination - source.filter { $0 < destination }.count
        places.insert(contentsOf: moving, at: max(0, min(insertAt, places.count)))
        save()
    }

    func setUsualDock(stationID: String?, stationName: String?, for placeID: UUID) {
        guard var place = place(id: placeID) else { return }
        place.usualStationID = stationID
        place.usualStationName = stationName
        // A station can't be both the usual and the backup dock.
        if stationID != nil, place.backupStationID == stationID {
            place.backupStationID = nil
            place.backupStationName = nil
        }
        update(place)
    }

    func setBackupDock(stationID: String?, stationName: String?, for placeID: UUID) {
        guard var place = place(id: placeID) else { return }
        guard stationID == nil || stationID != place.usualStationID else { return }
        place.backupStationID = stationID
        place.backupStationName = stationName
        update(place)
    }

    /// Trims whitespace and drops empty or duplicate aliases.
    private static func cleaned(_ place: SavedPlace) -> SavedPlace {
        var place = place
        place.name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen: Set<String> = [SavedPlace.normalizedName(place.name)]
        place.aliases = place.aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { alias in
                let normalized = SavedPlace.normalizedName(alias)
                return !normalized.isEmpty && seen.insert(normalized).inserted
            }
        return place
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: Self.storageKey)
        }
        onChange()
    }

    /// Loads every place that can still be read. A single damaged entry is
    /// skipped instead of losing the whole list; if nothing can be read,
    /// the raw data is kept under `unreadableBackupKey`.
    nonisolated static func load(from defaults: UserDefaults) -> [SavedPlace] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        if let entries = try? JSONDecoder().decode([LossyPlace].self, from: data) {
            return entries.compactMap(\.place)
        }
        defaults.set(data, forKey: unreadableBackupKey)
        return []
    }

    private nonisolated struct LossyPlace: Decodable {
        let place: SavedPlace?

        init(from decoder: Decoder) throws {
            place = try? SavedPlace(from: decoder)
        }
    }

    /// Tells Siri the saved-place names changed, so phrases that mention
    /// them ("…near school…") start working without reinstalling.
    nonisolated static func refreshSiriPhrases() {
        DockFinderShortcutsProvider.updateAppShortcutParameters()
    }
}
