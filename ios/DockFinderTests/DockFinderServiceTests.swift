//
//  DockFinderServiceTests.swift
//  DockFinderTests
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

struct DockFinderServiceTests {
    // Distances from `userLocation`: near ≈ 0 m, mid ≈ 450 m, far ≈ 1.2 km.
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)
    let far = info("far", "Atlantic Ave & Fort Greene Pl", 40.6840, -73.9765)

    private func select(
        _ information: [StationInformation],
        _ statuses: [StationStatus],
        statusUpdated: Date = referenceNow,
        from location: CLLocation = userLocation
    ) throws -> DockStation {
        try DockFinderService.nearestStation(
            to: location,
            information: informationFeed(information),
            status: statusFeed(statuses, updated: statusUpdated),
            now: referenceNow
        )
    }

    @Test func selectsNearestEligibleStation() throws {
        let station = try select([far, mid, near], [status("far", docks: 3), status("mid", docks: 2), status("near", docks: 4)])
        #expect(station.id == "near")
        #expect(station.name == "Smith St & Bergen St")
        #expect(station.availableDocks == 4)
        #expect(station.straightLineDistance < 1)
        #expect(station.observedAt == referenceNow.addingTimeInterval(-30))
    }

    @Test func joinsInformationAndStatusByStationID() throws {
        // Status order differs from information order; join must use IDs.
        let station = try select([near, mid], [status("mid", docks: 9), status("near", docks: 1)])
        #expect(station.id == "near")
        #expect(station.availableDocks == 1)
        #expect(station.latitude == near.latitude)
    }

    @Test func excludesStationsWithZeroDocks() throws {
        let station = try select([near, mid], [status("near", docks: 0), status("mid", docks: 2)])
        #expect(station.id == "mid")
    }

    @Test func excludesStationsNotAcceptingReturns() throws {
        let station = try select([near, mid], [status("near", docks: 5, returning: false), status("mid", docks: 2)])
        #expect(station.id == "mid")
    }

    @Test func excludesUninstalledStations() throws {
        let station = try select([near, mid], [status("near", docks: 5, installed: false), status("mid", docks: 2)])
        #expect(station.id == "mid")
    }

    @Test func excludesStatusWithoutMatchingInformation() throws {
        let station = try select([mid], [status("near", docks: 5), status("mid", docks: 2)])
        #expect(station.id == "mid")
    }

    @Test func excludesStationsThatHaveNotReportedRecently() throws {
        let stale = referenceNow.addingTimeInterval(-(DockFinderService.maxStationReportAge + 1))
        let station = try select([near, mid], [status("near", docks: 5, reported: stale), status("mid", docks: 2)])
        #expect(station.id == "mid")
    }

    @Test func acceptsStationsWithoutReportTime() throws {
        let station = try select([near], [status("near", docks: 5, reported: nil)])
        #expect(station.id == "near")
        #expect(station.observedAt == nil)
    }

    @Test func staleFeedIsRejected() {
        let updated = referenceNow.addingTimeInterval(-(DockFinderService.maxFeedAge + 1))
        #expect(throws: DockFinderError.staleData(lastUpdated: updated)) {
            try select([near], [status("near", docks: 5)], statusUpdated: updated)
        }
    }

    @Test func emptyFeedsReportNoStationData() {
        #expect(throws: DockFinderError.noStationData) { try select([], [status("near", docks: 5)]) }
        #expect(throws: DockFinderError.noStationData) { try select([near], []) }
    }

    @Test func noEligibleStationsReportsNoAvailableDocks() {
        #expect(throws: DockFinderError.noAvailableDocks) {
            try select([near, mid], [status("near", docks: 0), status("mid", docks: 3, returning: false)])
        }
    }

    @Test func distantUserIsOutsideServiceArea() {
        let cupertino = CLLocation(latitude: 37.3349, longitude: -122.0090)
        #expect(throws: DockFinderError.outsideServiceArea) {
            try select([near], [status("near", docks: 5)], from: cupertino)
        }
    }

    // MARK: - End-to-end through the service

    @Test func findNearestDockCombinesLocationAndFeeds() async throws {
        let service = DockFinderService(
            location: StubLocation(result: .success(LocationFix(location: userLocation, isApproximate: true))),
            feeds: StubFeeds(
                information: .success(informationFeed([near, far])),
                status: .success(statusFeed([status("near", docks: 4), status("far", docks: 2)]))
            ),
            now: { referenceNow }
        )
        let result = try await service.findNearestDock()
        #expect(result.station.id == "near")
        #expect(result.locationIsApproximate)
    }

    @Test func locationErrorsPropagateBeforeAnyNetworkWork() async {
        let service = DockFinderService(
            location: StubLocation(result: .failure(.locationPermissionDenied)),
            feeds: StubFeeds(information: .failure(.networkUnavailable), status: .failure(.networkUnavailable)),
            now: { referenceNow }
        )
        await #expect(throws: DockFinderError.locationPermissionDenied) {
            try await service.findNearestDock()
        }
    }

    @Test func networkErrorsPropagate() async {
        let service = DockFinderService(
            location: StubLocation(result: .success(LocationFix(location: userLocation, isApproximate: false))),
            feeds: StubFeeds(information: .success(informationFeed([near])), status: .failure(.networkUnavailable)),
            now: { referenceNow }
        )
        await #expect(throws: DockFinderError.networkUnavailable) {
            try await service.findNearestDock()
        }
    }

    // MARK: - Spoken summary

    @Test func summaryUsesRealStationData() {
        let station = DockStation(
            id: "x", name: "Smith St & Bergen St", latitude: 0, longitude: 0,
            availableDocks: 1, straightLineDistance: 300, observedAt: nil
        )
        let precise = DockSearchResult(station: station, locationIsApproximate: false)
        #expect(precise.summary.contains("Smith St & Bergen St"))
        #expect(precise.summary.contains("1 open dock."))
        #expect(precise.summary.contains("straight line"))
        #expect(!precise.summary.contains("approximate"))

        let approximate = DockSearchResult(station: station, locationIsApproximate: true)
        #expect(approximate.summary.contains("approximate"))
    }
}
