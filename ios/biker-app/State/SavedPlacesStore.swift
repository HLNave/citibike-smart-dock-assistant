//
//  SavedPlacesStore.swift
//  Dock Finder
//
//  The rider's regular destinations (school, work, home…): what they call
//  each one, its usual and backup docks, and how early to warn them on a
//  ride. Stored on this device only. Siri phrases like "Ask Dock Finder to
//  find a dock near school" are built from this list.
//

import AppIntents
import CoreLocation
import Foundation
import Observation

nonisolated struct SavedPlace: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// How far out a ride announces the best dock, unless the place says otherwise.
    static let defaultAlertDistance: CLLocationDistance = 500
    /// The alert radius the rider can pick on the map. iOS geofences can
    /// fire late or not at all when they're smaller than about 150 m, and
    /// from farther than 1.5 km (about 8 minutes by bike) the dock answer
    /// is stale by the time the rider gets there.
    static let alertDistanceRange: ClosedRange<CLLocationDistance> = 150...1_500
    /// The slider moves in steps this size, so radii read as round numbers.
    static let alertDistanceStep: CLLocationDistance = 50
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
    /// Say where to dock when the rider bikes up to this place, even
    /// without a ride (see PlaceArrivalMonitor).
    var arrivalAlerts: Bool

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
        alertDistance: CLLocationDistance = SavedPlace.defaultAlertDistance,
        arrivalAlerts: Bool = true
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
        self.arrivalAlerts = arrivalAlerts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, latitude, longitude, address
        case usualStationID, usualStationName, backupStationID, backupStationName, alertDistance, arrivalAlerts
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
        alertDistance = Self.clampedAlertDistance(distance)
        arrivalAlerts = try container.decodeIfPresent(Bool.self, forKey: .arrivalAlerts) ?? true
    }

    /// Keeps an alert radius within `alertDistanceRange`. A missing or
    /// nonsense value (zero, negative) falls back to the default instead.
    static func clampedAlertDistance(_ distance: CLLocationDistance) -> CLLocationDistance {
        guard distance.isFinite, distance > 0 else { return defaultAlertDistance }
        return min(max(distance, alertDistanceRange.lowerBound), alertDistanceRange.upperBound)
    }

    /// Rounds a slider position to the nearest `alertDistanceStep` within
    /// `alertDistanceRange`: 512 → 500, 20 → 150.
    static func snappedAlertDistance(_ distance: CLLocationDistance) -> CLLocationDistance {
        guard !distance.isNaN else { return defaultAlertDistance }
        let snapped = (distance / alertDistanceStep).rounded() * alertDistanceStep
        return min(max(snapped, alertDistanceRange.lowerBound), alertDistanceRange.upperBound)
    }

    var destination: Destination {
        Destination(name: name, latitude: latitude, longitude: longitude, address: address)
    }

    /// This place set to `location` with a new alert radius. The address
    /// only changes if the pin actually moved, so saving without moving it
    /// keeps the address the rider originally picked.
    func relocated(to location: Destination, alertDistance: CLLocationDistance) -> SavedPlace {
        var place = self
        place.alertDistance = alertDistance
        if location.latitude != latitude || location.longitude != longitude {
            place.latitude = location.latitude
            place.longitude = location.longitude
            place.address = location.address ?? location.name
        }
        return place
    }

    /// The usual and backup docks that are farther than the dock search
    /// covers from `location`, e.g. after the place was moved on the map.
    /// Dock Finder still checks them first, so the rider is warned rather
    /// than having them cleared.
    func distantDocks(from location: CLLocation, in stations: [StationInformation]) -> [(name: String, distance: CLLocationDistance)] {
        [(usualStationID, usualStationName), (backupStationID, backupStationName)].compactMap { id, name in
            guard let id, let station = stations.first(where: { $0.stationID == id }) else { return nil }
            let distance = location.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
            guard distance > StationNetwork.nearbyRadius else { return nil }
            return (name ?? station.name, distance)
        }
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
    static let shared = SavedPlacesStore(backup: KeychainPlacesBackup()) {
        SavedPlacesStore.refreshSiriPhrases()
        // Watch the new or changed places for arrivals.
        Task { await PlaceArrivalMonitor.shared.sync() }
    }
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
    private let backup: (any PlacesBackup)?
    private let onChange: () -> Void

    private(set) var places: [SavedPlace]

    init(
        defaults: UserDefaults = .standard,
        backup: (any PlacesBackup)? = nil,
        onChange: @escaping () -> Void = SavedPlacesStore.refreshSiriPhrases
    ) {
        self.defaults = defaults
        self.backup = backup
        self.onChange = onChange
        // A fresh install has nothing saved yet; bring back the places from
        // before the app was deleted, if a backup survived.
        if defaults.data(forKey: Self.storageKey) == nil, let saved = backup?.read() {
            defaults.set(saved, forKey: Self.storageKey)
            places = Self.load(from: defaults)
            if !places.isEmpty { onChange() }
        } else {
            places = Self.load(from: defaults)
        }
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

    /// Trims whitespace, drops empty or duplicate aliases and keeps the
    /// alert radius in range.
    private static func cleaned(_ place: SavedPlace) -> SavedPlace {
        var place = place
        place.name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        place.alertDistance = SavedPlace.clampedAlertDistance(place.alertDistance)
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
            backup?.write(data)
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
