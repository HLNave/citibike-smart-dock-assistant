//
//  DockFinderService.swift
//  Dock Finder
//
//  Every on-device feature: nearest dock, dock near a destination (with
//  the usual-dock check), one station's status, and citywide totals. Siri
//  and the app UI both go through this type.
//

import CoreLocation
import Foundation

nonisolated struct DockFinderService: Sendable {
    /// The live service: real location, real Citi Bike data.
    @MainActor static var live: DockFinderService {
        DockFinderService(location: LocationService.shared, feeds: CachedStationFeeds.shared)
    }

    static let maxFeedAge = StationNetwork.maxFeedAge
    static let maxStationReportAge = StationNetwork.maxStationReportAge
    /// Beyond this straight-line distance the user is treated as outside
    /// Citi Bike's service area.
    static let maxSearchDistance: CLLocationDistance = 10_000

    private let location: any LocationProviding
    private let feeds: any CitiBikeFeedProviding
    private let now: @Sendable () -> Date

    init(location: any LocationProviding, feeds: any CitiBikeFeedProviding, now: @escaping @Sendable () -> Date = Date.init) {
        self.location = location
        self.feeds = feeds
        self.now = now
    }

    // MARK: - Features

    /// Finds the nearest station to the rider that has room to return a bike.
    func findNearestDock() async throws -> DockSearchResult {
        let fix = try await location.currentLocation()
        let network = try await loadNetwork()
        let station = try Self.nearestStation(to: fix.location, in: network)
        return DockSearchResult(station: station, locationIsApproximate: fix.isApproximate)
    }

    /// Finds a dock near a destination. If the rider has a usual dock there,
    /// it's preferred while it has room; otherwise the answer says why and
    /// reroutes to the nearest station with space.
    func findDock(near destination: Destination, usualStationID: String? = nil) async throws -> DestinationDockResult {
        Self.dock(near: destination, usualStationID: usualStationID, in: try await loadNetwork())
    }

    /// Live status of one station, matched by ID or by a spoken name.
    func checkStation(_ idOrName: String) async throws -> StationCheckResult {
        let network = try await loadNetwork()
        guard let station = network.bestMatch(for: idOrName) else {
            throw DockFinderError.stationNotFound(idOrName)
        }
        return Self.check(station, in: network)
    }

    func citywideSummary() async throws -> NetworkSummary {
        try await loadNetwork().summary
    }

    /// Every station's name and location, for pickers and name matching.
    func stationDirectory() async throws -> [StationInformation] {
        try await feeds.fetchStationInformation().data.stations
    }

    func loadNetwork() async throws -> StationNetwork {
        async let information = feeds.fetchStationInformation()
        async let status = feeds.fetchStationStatus()
        let (informationFeed, statusFeed) = try await (information, status)
        return try StationNetwork(information: informationFeed, status: statusFeed, now: now())
    }

    // MARK: - Pure selection logic

    static func nearestStation(
        to location: CLLocation,
        information: GBFSFeed<StationInformationPayload>,
        status: GBFSFeed<StationStatusPayload>,
        now: Date
    ) throws -> DockStation {
        try nearestStation(to: location, in: StationNetwork(information: information, status: status, now: now))
    }

    static func nearestStation(to location: CLLocation, in network: StationNetwork) throws -> DockStation {
        guard let nearest = network.returnableStations(around: location).first else {
            throw DockFinderError.noAvailableDocks
        }
        guard nearest.straightLineDistance <= maxSearchDistance else {
            throw DockFinderError.outsideServiceArea
        }
        return nearest
    }

    static func dock(near destination: Destination, usualStationID: String?, in network: StationNetwork) -> DestinationDockResult {
        let usual = usualStationID.flatMap { network.station(id: $0) }
        let usualProblem = usual.flatMap { network.problem(with: $0) }

        if let usual, usualProblem == nil {
            let distance = destination.location.distance(from: usual.location)
            return DestinationDockResult(
                destination: destination,
                usualDock: usual,
                usualDockProblem: nil,
                selected: DockStation(snapshot: usual, distance: distance)
            )
        }

        let selected = network.returnableStations(
            around: destination.location,
            within: StationNetwork.nearbyRadius,
            excluding: usual?.id
        ).first
        return DestinationDockResult(destination: destination, usualDock: usual, usualDockProblem: usualProblem, selected: selected)
    }

    static func check(_ station: StationSnapshot, in network: StationNetwork) -> StationCheckResult {
        let problem = network.problem(with: station)
        let alternative = problem == nil ? nil : network.returnableStations(
            around: station.location,
            within: StationNetwork.nearbyRadius,
            excluding: station.id
        ).first
        return StationCheckResult(station: station, problem: problem, alternative: alternative)
    }
}
