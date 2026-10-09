//
//  Entities.swift
//  Dock Finder
//
//  Saved places and Citi Bike stations as things Siri and Shortcuts can
//  ask for: "Find a dock near school", "Which station?".
//

import AppIntents
import Foundation

struct SavedPlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Place"
    static let defaultQuery = SavedPlaceQuery()

    let id: UUID
    let name: String
    let usualDockName: String?

    init(_ place: SavedPlace) {
        id = place.id
        name = place.name
        usualDockName = place.usualStationName
    }

    var displayRepresentation: DisplayRepresentation {
        if let usualDockName {
            DisplayRepresentation(title: "\(name)", subtitle: "Usual dock: \(usualDockName)")
        } else {
            DisplayRepresentation(title: "\(name)")
        }
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

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
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

    /// The rider's usual docks, so the Shortcuts picker isn't a list of 2,000 stations.
    @MainActor
    func suggestedEntities() async throws -> [StationEntity] {
        var seen = Set<String>()
        return SavedPlacesStore.shared.places.compactMap { place in
            guard let id = place.usualStationID, let name = place.usualStationName, seen.insert(id).inserted else { return nil }
            return StationEntity(id: id, name: name)
        }
    }
}
