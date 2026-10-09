//
//  DockFinderService.swift
//  Dock Finder
//
//  The single dock-finding pipeline used by both Siri and the app UI.
//

import CoreLocation
import Foundation

nonisolated struct DockFinderService: Sendable {
    /// The live service: real location, real Citi Bike data.
    @MainActor static var live: DockFinderService {
        DockFinderService(location: LocationService.shared, feeds: CitiBikeAPIClient())
    }

    /// The status feed must have been refreshed this recently to be trusted.
    static let maxFeedAge: TimeInterval = 15 * 60
    /// Stations that have not reported within this window are skipped.
    static let maxStationReportAge: TimeInterval = 60 * 60
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

    /// Finds the nearest station accepting returns with at least one open dock.
    func findNearestDock() async throws -> DockSearchResult {
        let fix = try await location.currentLocation()

        async let information = feeds.fetchStationInformation()
        async let status = feeds.fetchStationStatus()
        let (informationFeed, statusFeed) = try await (information, status)

        let station = try Self.nearestStation(
            to: fix.location,
            information: informationFeed,
            status: statusFeed,
            now: now()
        )
        return DockSearchResult(station: station, locationIsApproximate: fix.isApproximate)
    }

    /// Pure selection logic: join, filter, and pick the nearest eligible station.
    static func nearestStation(
        to location: CLLocation,
        information: GBFSFeed<StationInformationPayload>,
        status: GBFSFeed<StationStatusPayload>,
        now: Date
    ) throws -> DockStation {
        guard !information.data.stations.isEmpty, !status.data.stations.isEmpty else {
            throw DockFinderError.noStationData
        }
        guard now.timeIntervalSince(status.lastUpdated) <= maxFeedAge else {
            throw DockFinderError.staleData(lastUpdated: status.lastUpdated)
        }

        let infoByID = Dictionary(
            information.data.stations.map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let candidates: [DockStation] = status.data.stations.compactMap { status in
            guard status.isInstalled,
                  status.isReturning,
                  status.numDocksAvailable > 0,
                  let info = infoByID[status.stationID],
                  CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: info.latitude, longitude: info.longitude))
            else { return nil }

            if let reported = status.lastReported, now.timeIntervalSince(reported) > maxStationReportAge {
                return nil
            }

            let distance = location.distance(from: CLLocation(latitude: info.latitude, longitude: info.longitude))
            return DockStation(
                id: info.stationID,
                name: info.name,
                latitude: info.latitude,
                longitude: info.longitude,
                availableDocks: status.numDocksAvailable,
                straightLineDistance: distance,
                observedAt: status.lastReported
            )
        }

        guard let nearest = candidates.min(by: { $0.straightLineDistance < $1.straightLineDistance }) else {
            throw DockFinderError.noAvailableDocks
        }
        guard nearest.straightLineDistance <= maxSearchDistance else {
            throw DockFinderError.outsideServiceArea
        }
        return nearest
    }
}
