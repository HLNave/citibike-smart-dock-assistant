//
//  Entities.swift
//  Dock Finder
//
//  Saved places and Citi Bike stations as things Siri and Shortcuts can
//  fill in: "Ask Dock Finder to find a dock near school", "…to check
//  Mercer and Bleecker".
//

import AppIntents
import CoreLocation
import Foundation

struct SavedPlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Place"
    static let defaultQuery = SavedPlaceQuery()

    let id: UUID
    let name: String
    let aliases: [String]
    let usualDockName: String?

    init(_ place: SavedPlace) {
        id = place.id
        name = place.name
        aliases = place.aliases
        usualDockName = place.usualStationName
    }

    /// Nicknames are synonyms, so "…near Stern" works when School is also
    /// called Stern.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: usualDockName.map { LocalizedStringResource("Usual dock: \($0)") },
            synonyms: aliases.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }
}

struct SavedPlaceQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SavedPlaceEntity] {
        SavedPlacesStore.shared.places
            .filter { identifiers.contains($0.id) }
            .map(SavedPlaceEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SavedPlaceEntity] {
        SavedPlacesStore.shared.places
            .filter { $0.matches(string) || $0.name.localizedCaseInsensitiveContains(string) }
            .map(SavedPlaceEntity.init)
    }

    /// Also the list Siri matches against in "Find a dock near school".
    @MainActor
    func suggestedEntities() async throws -> [SavedPlaceEntity] {
        SavedPlacesStore.shared.places.map(SavedPlaceEntity.init)
    }
}

struct StationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Citi Bike Station"
    static let defaultQuery = StationQuery()

    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ station: StationInformation) {
        self.init(id: station.stationID, name: station.name)
    }

    /// The spoken form ("Mercer and Bleecker" for "Mercer St & Bleecker
    /// St") is a synonym, since that's how riders say it.
    var displayRepresentation: DisplayRepresentation {
        let spoken = Speech.stationName(name)
        return DisplayRepresentation(
            title: "\(name)",
            synonyms: spoken == name ? [] : [LocalizedStringResource(stringLiteral: spoken)]
        )
    }
}

struct StationQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        try await DockFinderService.live.stationDirectory()
            .filter { identifiers.contains($0.stationID) }
            .map(StationEntity.init)
    }

    /// Siri passes what the rider said; the closest few names are offered.
    @MainActor
    func entities(matching string: String) async throws -> [StationEntity] {
        try await DockFinderService.live.stationDirectory()
            .map { (station: $0, score: StationNameMatcher.score(name: $0.name, query: string)) }
            .filter { $0.score >= StationNameMatcher.threshold }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { StationEntity($0.station) }
    }

    /// The stations Siri can recognize in "Ask Dock Finder to check …"
    /// (and the Shortcuts picker, instead of 2,000 stations): usual and
    /// backup docks, recently checked stations, and the few nearest each
    /// saved place. Siri can't take the whole system.
    @MainActor
    func suggestedEntities() async throws -> [StationEntity] {
        var seen = Set<String>()
        var result: [StationEntity] = []
        func add(_ id: String?, _ name: String?) {
            guard let id, let name, seen.insert(id).inserted else { return }
            result.append(StationEntity(id: id, name: name))
        }
        let places = SavedPlacesStore.shared.places
        for place in places {
            add(place.usualStationID, place.usualStationName)
            add(place.backupStationID, place.backupStationName)
        }
        for recent in RecentStations.shared.stations {
            add(recent.id, recent.name)
        }
        if let directory = try? await DockFinderService.live.stationDirectory() {
            for place in places {
                let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let nearest = directory
                    .map { (station: $0, distance: here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                    .sorted { $0.distance < $1.distance }
                    .prefix(Self.nearestPerPlace)
                for near in nearest {
                    add(near.station.stationID, near.station.name)
                }
            }
        }
        return Array(result.prefix(Self.maxSuggested))
    }

    static let nearestPerPlace = 4
    static let maxSuggested = 60
}

/// Stations the rider asked about recently, newest first, so they can be
/// named straight in a Siri phrase next time.
@MainActor
final class RecentStations {
    static let shared = RecentStations()
    static let limit = 15
    private static let storageKey = "recentStations"

    struct Station: Codable, Equatable {
        let id: String
        let name: String
    }

    private let defaults: UserDefaults
    private(set) var stations: [Station]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stations = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Station].self, from: $0) } ?? []
    }

    /// Moves the station to the front. Siri's phrase list is only refreshed
    /// when it wasn't already in it.
    func add(id: String, name: String) {
        let isNew = !stations.contains { $0.id == id }
        stations.removeAll { $0.id == id }
        stations.insert(Station(id: id, name: name), at: 0)
        stations = Array(stations.prefix(Self.limit))
        if let data = try? JSONEncoder().encode(stations) {
            defaults.set(data, forKey: Self.storageKey)
        }
        if isNew {
            SavedPlacesStore.refreshSiriPhrases()
        }
    }
}
