//
//  TestSupport.swift
//  DockFinderTests
//

import CoreLocation
import Foundation
@testable import DockFinder

let referenceNow = Date(timeIntervalSince1970: 1_791_498_400)

/// Smith St & Bergen St, Brooklyn — the user's position in most tests.
let userLocation = CLLocation(latitude: 40.6861, longitude: -73.9906)

func info(_ id: String, _ name: String, _ lat: Double, _ lon: Double) -> StationInformation {
    StationInformation(stationID: id, name: name, latitude: lat, longitude: lon)
}

func status(
    _ id: String,
    docks: Int,
    bikes: Int = 0,
    ebikes: Int = 0,
    installed: Bool = true,
    returning: Bool = true,
    reported: Date? = referenceNow.addingTimeInterval(-30)
) -> StationStatus {
    StationStatus(
        stationID: id, numDocksAvailable: docks, numBikesAvailable: bikes, numEbikesAvailable: ebikes,
        isInstalled: installed, isReturning: returning, lastReported: reported
    )
}

func informationFeed(_ stations: [StationInformation], updated: Date = referenceNow) -> GBFSFeed<StationInformationPayload> {
    GBFSFeed(lastUpdated: updated, ttl: 60, data: StationInformationPayload(stations: stations))
}

func statusFeed(_ stations: [StationStatus], updated: Date = referenceNow) -> GBFSFeed<StationStatusPayload> {
    GBFSFeed(lastUpdated: updated, ttl: 60, data: StationStatusPayload(stations: stations))
}

struct StubFeeds: CitiBikeFeedProviding {
    var information: Result<GBFSFeed<StationInformationPayload>, DockFinderError>
    var status: Result<GBFSFeed<StationStatusPayload>, DockFinderError>

    func fetchStationInformation() async throws -> GBFSFeed<StationInformationPayload> {
        try information.get()
    }

    func fetchStationStatus() async throws -> GBFSFeed<StationStatusPayload> {
        try status.get()
    }
}

struct StubLocation: LocationProviding {
    var result: Result<LocationFix, DockFinderError>

    func currentLocation() async throws -> LocationFix {
        try result.get()
    }
}
