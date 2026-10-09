//
//  CitiBikeAPIClientTests.swift
//  DockFinderTests
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

struct CitiBikeAPIClientTests {
    // Shapes mirror the live Citi Bike feeds, which encode booleans as 0/1.
    let informationJSON = """
    {"data": {"stations": [
      {"station_id": "a", "name": "Smith St & Bergen St", "lat": 40.6861, "lon": -73.9906, "capacity": 23},
      {"station_id": "b", "name": "Court St & State St", "lat": 40.69, "lon": -73.992}
    ]}, "last_updated": 1791498365, "ttl": 60, "version": "2.3"}
    """

    let statusJSON = """
    {"data": {"stations": [
      {"station_id": "a", "num_docks_available": 4, "is_installed": 1, "is_renting": 1, "is_returning": 1, "last_reported": 1791498300},
      {"station_id": "b", "num_docks_available": 0, "is_installed": true, "is_renting": false, "is_returning": false}
    ]}, "last_updated": 1791498427, "ttl": 60}
    """

    private func client(returning body: String, statusCode: Int = 200) -> CitiBikeAPIClient {
        CitiBikeAPIClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test func decodesStationInformation() async throws {
        let feed = try await client(returning: informationJSON).fetchStationInformation()
        #expect(feed.lastUpdated == Date(timeIntervalSince1970: 1_791_498_365))
        #expect(feed.ttl == 60)
        #expect(feed.data.stations == [
            StationInformation(stationID: "a", name: "Smith St & Bergen St", latitude: 40.6861, longitude: -73.9906),
            StationInformation(stationID: "b", name: "Court St & State St", latitude: 40.69, longitude: -73.992),
        ])
    }

    @Test func decodesStationStatusWithIntegerAndBooleanFlags() async throws {
        let feed = try await client(returning: statusJSON).fetchStationStatus()
        #expect(feed.data.stations == [
            StationStatus(stationID: "a", numDocksAvailable: 4, isInstalled: true, isReturning: true,
                          lastReported: Date(timeIntervalSince1970: 1_791_498_300)),
            StationStatus(stationID: "b", numDocksAvailable: 0, isInstalled: true, isReturning: false, lastReported: nil),
        ])
    }

    @Test func skipsIndividuallyMalformedStations() async throws {
        let json = """
        {"data": {"stations": [
          {"station_id": "a", "num_docks_available": 4, "is_installed": 1, "is_returning": 1},
          {"station_id": "b", "num_docks_available": "lots", "is_installed": 1, "is_returning": 1},
          {"station_id": "c", "is_installed": 1, "is_returning": 1},
          {"station_id": "d", "num_docks_available": 2, "is_installed": 1, "is_returning": "maybe"}
        ]}, "last_updated": 1791498427, "ttl": 60}
        """
        let feed = try await client(returning: json).fetchStationStatus()
        #expect(feed.data.stations.map(\.stationID) == ["a"])
    }

    @Test func emptyStationListDecodes() async throws {
        let json = #"{"data": {"stations": []}, "last_updated": 1791498427, "ttl": 60}"#
        let feed = try await client(returning: json).fetchStationStatus()
        #expect(feed.data.stations.isEmpty)
    }

    @Test(arguments: [
        "",
        "not json",
        "{}",
        #"{"data": {"stations": []}}"#,
        #"{"last_updated": 1791498427, "data": {}}"#,
        #"{"last_updated": "yesterday", "data": {"stations": []}}"#,
        #"[1, 2, 3]"#,
    ])
    func malformedFeedsThrowMalformedData(body: String) async {
        await #expect(throws: DockFinderError.malformedData) {
            try await client(returning: body).fetchStationStatus()
        }
    }

    @Test func httpErrorsThrowServiceUnavailable() async {
        await #expect(throws: DockFinderError.serviceUnavailable(statusCode: 503)) {
            try await client(returning: "", statusCode: 503).fetchStationInformation()
        }
    }

    @Test func connectivityErrorsThrowNetworkUnavailable() async {
        let offline = CitiBikeAPIClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: DockFinderError.networkUnavailable) {
            try await offline.fetchStationStatus()
        }
    }

    @Test func requestsBypassTheLocalCache() async throws {
        let seen = RequestRecorder()
        let client = CitiBikeAPIClient { request in
            await seen.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(statusJSON.utf8), response)
        }
        _ = try await client.fetchStationStatus()
        let request = try #require(await seen.requests.first)
        #expect(request.url == CitiBikeAPIClient.stationStatusURL)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    /// Hits the real Citi Bike feeds. Opt in with
    /// `TEST_RUNNER_DOCKFINDER_LIVE_TESTS=1 xcodebuild test …`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOCKFINDER_LIVE_TESTS"] == "1"))
    func liveFeedsDecodeAndYieldAStation() async throws {
        let client = CitiBikeAPIClient()
        async let information = client.fetchStationInformation()
        async let status = client.fetchStationStatus()
        let (informationFeed, statusFeed) = try await (information, status)
        #expect(informationFeed.data.stations.count > 500)
        #expect(statusFeed.data.stations.count > 500)

        let station = try DockFinderService.nearestStation(
            to: userLocation, information: informationFeed, status: statusFeed, now: Date()
        )
        #expect(station.availableDocks > 0)
        #expect(station.straightLineDistance < 2_000)
    }
}

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}
