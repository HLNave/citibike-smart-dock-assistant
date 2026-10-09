//
//  StationNetwork.swift
//  Dock Finder
//
//  One snapshot of the Citi Bike system: station metadata joined with live
//  status, plus the rules for whether a station is worth riding to. The
//  rules match the n8n workflow so the app and the backend agree.
//

import CoreLocation
import Foundation

/// A station with its live availability.
nonisolated struct StationSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let openDocks: Int
    let bikesAvailable: Int
    let ebikesAvailable: Int
    let isInstalled: Bool
    let isReturning: Bool
    let lastReported: Date?

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var spokenName: String { Speech.stationName(name) }
}

/// Why a station isn't a good place to return a bike.
nonisolated enum StationProblem: Sendable, Equatable {
    case closed
    case notReporting
    case full
    case almostFull

    /// Completes "Mercer and Bleecker …" / "Your usual dock …".
    var phrase: String {
        switch self {
        case .closed: "is closed"
        case .notReporting: "isn't reporting right now"
        case .full: "is full"
        case .almostFull: "is almost full"
        }
    }
}

nonisolated struct StationNetwork: Sendable {
    /// A station needs at least this many open docks to be recommended.
    /// A single open dock is often broken or taken by the time you arrive.
    static let minimumOpenDocks = 2
    /// How far from a destination (or another station) to look for docks.
    static let nearbyRadius: CLLocationDistance = 1_200
    /// The status feed must have been refreshed this recently to be trusted.
    static let maxFeedAge: TimeInterval = 15 * 60
    /// Stations that have not reported within this window are skipped.
    static let maxStationReportAge: TimeInterval = 60 * 60

    let stations: [StationSnapshot]
    let lastUpdated: Date
    let now: Date

    init(
        information: GBFSFeed<StationInformationPayload>,
        status: GBFSFeed<StationStatusPayload>,
        now: Date
    ) throws {
        guard !information.data.stations.isEmpty, !status.data.stations.isEmpty else {
            throw DockFinderError.noStationData
        }
        guard now.timeIntervalSince(status.lastUpdated) <= Self.maxFeedAge else {
            throw DockFinderError.staleData(lastUpdated: status.lastUpdated)
        }

        let infoByID = Dictionary(
            information.data.stations.map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        stations = status.data.stations.compactMap { status in
            guard let info = infoByID[status.stationID],
                  CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: info.latitude, longitude: info.longitude))
            else { return nil }
            return StationSnapshot(
                id: info.stationID,
                name: info.name,
                latitude: info.latitude,
                longitude: info.longitude,
                openDocks: status.numDocksAvailable,
                bikesAvailable: status.numBikesAvailable,
                ebikesAvailable: status.numEbikesAvailable,
                isInstalled: status.isInstalled,
                isReturning: status.isReturning,
                lastReported: status.lastReported
            )
        }
        lastUpdated = status.lastUpdated
        self.now = now
    }

    /// `nil` when the station is a good place to return a bike.
    func problem(with station: StationSnapshot) -> StationProblem? {
        if !station.isInstalled || !station.isReturning { return .closed }
        if let reported = station.lastReported, now.timeIntervalSince(reported) > Self.maxStationReportAge {
            return .notReporting
        }
        if station.openDocks == 0 { return .full }
        if station.openDocks < Self.minimumOpenDocks { return .almostFull }
        return nil
    }

    func canReturn(_ station: StationSnapshot) -> Bool {
        problem(with: station) == nil
    }

    /// Stations you can return to, nearest first (ties go to more open docks).
    func returnableStations(
        around location: CLLocation,
        within radius: CLLocationDistance? = nil,
        excluding excludedID: String? = nil
    ) -> [DockStation] {
        stations
            .filter { $0.id != excludedID && canReturn($0) }
            .map { DockStation(snapshot: $0, distance: location.distance(from: $0.location)) }
            .filter { radius == nil || $0.straightLineDistance <= radius! }
            .sorted {
                ($0.straightLineDistance, -$0.availableDocks) < ($1.straightLineDistance, -$1.availableDocks)
            }
    }

    func station(id: String) -> StationSnapshot? {
        stations.first { $0.id == id }
    }

    /// The station whose name best matches what the rider said, if any is close enough.
    func bestMatch(for query: String) -> StationSnapshot? {
        if let exact = station(id: query) { return exact }
        let ranked = stations
            .map { (station: $0, score: StationNameMatcher.score(name: $0.name, query: query)) }
            .filter { $0.score >= StationNameMatcher.threshold }
            .sorted { ($0.score, -$0.station.name.count) > ($1.score, -$1.station.name.count) }
        return ranked.first?.station
    }

    var summary: NetworkSummary {
        var summary = NetworkSummary()
        for station in stations {
            summary.bikesAvailable += station.bikesAvailable
            summary.ebikesAvailable += station.ebikesAvailable
            summary.openDocks += station.openDocks
            guard station.isInstalled else { continue }
            summary.activeStations += 1
            if station.isReturning, station.openDocks == 0 { summary.fullStations += 1 }
        }
        return summary
    }
}

extension DockStation {
    nonisolated init(snapshot: StationSnapshot, distance: CLLocationDistance) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            availableDocks: snapshot.openDocks,
            straightLineDistance: distance,
            observedAt: snapshot.lastReported
        )
    }
}
