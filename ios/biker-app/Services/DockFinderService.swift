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
        DockFinderService(location: LocationService.shared, feeds: CachedStationFeeds.shared, walking: MapKitWalkingDistances())
    }

    static let maxFeedAge = StationNetwork.maxFeedAge
    static let maxStationReportAge = StationNetwork.maxStationReportAge
    /// Beyond this straight-line distance the user is treated as outside
    /// Citi Bike's service area.
    static let maxSearchDistance: CLLocationDistance = 10_000

    /// How long a quick answer waits for Apple Maps' walking distances.
    static let quickMapsTimeLimit: Duration = .milliseconds(1_500)
    /// How long directions wait for them; directions take longer to start anyway.
    static let directionsMapsTimeLimit: Duration = .seconds(4)

    private let location: any LocationProviding
    private let feeds: any CitiBikeFeedProviding
    private let walking: any WalkingDistanceProviding
    private let now: @Sendable () -> Date

    init(
        location: any LocationProviding,
        feeds: any CitiBikeFeedProviding,
        now: @escaping @Sendable () -> Date = Date.init,
        walking: any WalkingDistanceProviding = NoWalkingDistances()
    ) {
        self.location = location
        self.feeds = feeds
        self.walking = walking
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
    /// When choosing among docks, Apple Maps' walking distances are used if
    /// they arrive within `mapsTimeLimit`.
    func findDock(
        near destination: Destination,
        usualStationID: String? = nil,
        backupStationID: String? = nil,
        from origin: CLLocation? = nil,
        mapsTimeLimit: Duration = DockFinderService.quickMapsTimeLimit
    ) async throws -> DestinationDockResult {
        let start: CLLocation?
        if let origin {
            start = origin
        } else {
            start = await location.recentLocation()
        }
        let network = try await loadNetwork()
        let estimated = Self.dock(
            near: destination,
            usualStationID: usualStationID,
            backupStationID: backupStationID,
            from: start,
            in: network
        )
        // The usual or backup dock is used as is; Maps only helps choose
        // between docks.
        guard estimated.selected != nil, !estimated.usesUsualDock, !estimated.selectedIsBackup else { return estimated }

        let excluded = Set([usualStationID, backupStationID].compactMap { $0 })
        let shortlist = Self.shortlist(Self.candidates(near: destination, excluding: excluded, in: network), near: destination.location)
        guard shortlist.count > 1 else { return estimated }
        let measured = await walking.walkingDistances(to: destination.location, from: shortlist, timeLimit: mapsTimeLimit)
        guard !measured.isEmpty else { return estimated }
        return Self.dock(
            near: destination,
            usualStationID: usualStationID,
            backupStationID: backupStationID,
            from: start,
            walkingDistances: measured,
            in: network
        )
    }

    /// A saved place's usual and backup docks, checked in that order.
    func findDock(
        for place: SavedPlace,
        from origin: CLLocation? = nil,
        mapsTimeLimit: Duration = DockFinderService.quickMapsTimeLimit
    ) async throws -> DestinationDockResult {
        try await findDock(
            near: place.destination,
            usualStationID: place.usualStationID,
            backupStationID: place.backupStationID,
            from: origin,
            mapsTimeLimit: mapsTimeLimit
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
        walkingDistances measured: [String: CLLocationDistance] = [:],
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
        let selected = bestDock(
            among: candidates(near: destination, excluding: excluded, in: network),
            near: destination.location,
            from: origin,
            walkingDistances: measured
        )
        return DestinationDockResult(
            destination: destination,
            usualDock: usual,
            usualDockProblem: usualProblem,
            selected: selected,
            skippedNearest: usual == nil ? network.skippedNearest(to: destination.location, chosenID: selected?.id) : nil
        )
    }

    /// Docks within this much extra walking of the closest one count as
    /// equally good, so the one on the rider's way can win. About half a
    /// short Manhattan block.
    static let onTheWayMargin: CLLocationDistance = 50
    /// How many of the closest docks get a real walking distance from Maps.
    static let shortlistSize = 3

    /// Docks with room near a destination, other than `excluded`.
    static func candidates(near destination: Destination, excluding excluded: Set<String>, in network: StationNetwork) -> [DockStation] {
        network.returnableStations(around: destination.location, within: StationNetwork.nearbyRadius)
            .filter { !excluded.contains($0.id) }
    }

    /// The docks with the shortest street-grid walk to `destination`.
    static func shortlist(_ candidates: [DockStation], near destination: CLLocation) -> [DockStation] {
        Array(rankedByWalk(candidates, near: destination, measured: [:]).prefix(shortlistSize).map { $0.station })
    }

    /// The dock to recommend near a destination: the shortest walk (ties go
    /// to more open docks). With Maps' walking distances (`measured`, by
    /// station ID), only the shortlist is considered, and any dock Maps
    /// didn't answer for keeps its street-grid estimate. When the rider's
    /// location is known, the docks within `onTheWayMargin` of the shortest
    /// walk are treated as tied, and the shortest ride from the rider wins.
    static func bestDock(
        among candidates: [DockStation],
        near destination: CLLocation,
        from origin: CLLocation?,
        walkingDistances measured: [String: CLLocationDistance] = [:]
    ) -> DockStation? {
        let pool = measured.isEmpty ? candidates : shortlist(candidates, near: destination)
        let ranked = rankedByWalk(pool, near: destination, measured: measured)
        guard let closest = ranked.first else { return nil }
        guard let origin else { return closest.station }
        let tied = ranked.filter { $0.walk <= closest.walk + onTheWayMargin }
        let rides = tied.map { (station: $0.station, ride: StreetGrid.distance(from: origin, to: $0.station.location)) }
        // `min` keeps the first of equal rides, so a tie stays with the shorter walk.
        return rides.min { $0.ride < $1.ride }?.station
    }

    private static func rankedByWalk(
        _ stations: [DockStation],
        near destination: CLLocation,
        measured: [String: CLLocationDistance]
    ) -> [(station: DockStation, walk: CLLocationDistance)] {
        stations
            .map { (station: $0, walk: measured[$0.id] ?? StreetGrid.distance(from: destination, to: $0.location)) }
            .sorted { ($0.walk, -$0.station.availableDocks) < ($1.walk, -$1.station.availableDocks) }
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
