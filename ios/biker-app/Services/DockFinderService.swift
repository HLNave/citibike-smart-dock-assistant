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
        return DockSearchResult(
            station: station,
            locationIsApproximate: fix.isApproximate,
            avoided: network.skippedNearest(to: fix.location, chosenID: station.id)
        )
    }

    /// Finds a dock near a destination. If the rider has a usual dock there,
    /// it's preferred while it has room; then their backup dock; otherwise
    /// the answer says why and reroutes to the closest station with space,
    /// preferring one on the rider's way. `origin` is where the rider is
    /// coming from; without it, a recent location fix is used if iOS has one.
    func findDock(
        near destination: Destination,
        usualStationID: String? = nil,
        backupStationID: String? = nil,
        from origin: CLLocation? = nil
    ) async throws -> DestinationDockResult {
        let start: CLLocation?
        if let origin {
            start = origin
        } else {
            start = await location.recentLocation()
        }
        return Self.dock(
            near: destination,
            usualStationID: usualStationID,
            backupStationID: backupStationID,
            from: start,
            in: try await loadNetwork()
        )
    }

    /// A saved place's usual and backup docks, checked in that order.
    func findDock(for place: SavedPlace, from origin: CLLocation? = nil) async throws -> DestinationDockResult {
        try await findDock(
            near: place.destination,
            usualStationID: place.usualStationID,
            backupStationID: place.backupStationID,
            from: origin
        )
    }

    /// The rider's current location, or nil when it isn't available.
    func riderLocation() async -> CLLocation? {
        try? await location.currentLocation().location
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

    static func dock(
        near destination: Destination,
        usualStationID: String?,
        backupStationID: String? = nil,
        from origin: CLLocation? = nil,
        in network: StationNetwork
    ) -> DestinationDockResult {
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

        if let backup = backupStationID.flatMap({ network.station(id: $0) }),
           backup.id != usual?.id,
           network.canReturn(backup) {
            return DestinationDockResult(
                destination: destination,
                usualDock: usual,
                usualDockProblem: usualProblem,
                selected: DockStation(snapshot: backup, distance: destination.location.distance(from: backup.location)),
                selectedIsBackup: true
            )
        }

        let excluded: Set<String> = Set([usual?.id, backupStationID].compactMap { $0 })
        let candidates = network.returnableStations(around: destination.location, within: StationNetwork.nearbyRadius)
            .filter { !excluded.contains($0.id) }
        let selected = bestDock(among: candidates, near: destination.location, from: origin)
        return DestinationDockResult(
            destination: destination,
            usualDock: usual,
            usualDockProblem: usualProblem,
            selected: selected,
            skippedNearest: usual == nil ? network.skippedNearest(to: destination.location, chosenID: selected?.id) : nil
        )
    }

    /// Docks within this much extra walking of the closest one count as
    /// equally good, so the one on the rider's way can win. About one short
    /// Manhattan block.
    static let onTheWayMargin: CLLocationDistance = 100

    /// The dock to recommend near a destination: the shortest walk along
    /// the street grid (ties go to more open docks). When the rider's
    /// location is known, the docks within `onTheWayMargin` of that walk
    /// are treated as tied, and the shortest ride from the rider wins.
    static func bestDock(
        among candidates: [DockStation],
        near destination: CLLocation,
        from origin: CLLocation?
    ) -> DockStation? {
        let ranked = candidates
            .map { (station: $0, walk: StreetGrid.distance(from: destination, to: $0.location)) }
            .sorted { ($0.walk, -$0.station.availableDocks) < ($1.walk, -$1.station.availableDocks) }
        guard let closest = ranked.first else { return nil }
        guard let origin else { return closest.station }
        let tied = ranked.filter { $0.walk <= closest.walk + onTheWayMargin }
        let rides = tied.map { (station: $0.station, ride: StreetGrid.distance(from: origin, to: $0.station.location)) }
        // `min` keeps the first of equal rides, so a tie stays with the shorter walk.
        return rides.min { $0.ride < $1.ride }?.station
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
