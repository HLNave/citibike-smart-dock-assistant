//
//  FeatureTests.swift
//  DockFinderTests
//
//  Dock near a destination (with the usual-dock check), station checks,
//  and citywide totals.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

struct FeatureTests {
    // Distances from `school` (≈ the `near` station): near ≈ 0 m, mid ≈ 450 m,
    // far ≈ 1.2 km, outer ≈ 2.5 km.
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)
    let far = info("far", "Atlantic Ave & Fort Greene Pl", 40.6840, -73.9765)
    let outer = info("outer", "Myrtle Ave & St Edwards St", 40.6932, -73.9776)
    let school = Destination(name: "school", latitude: 40.6862, longitude: -73.9906)

    private func network(_ statuses: [StationStatus]) throws -> StationNetwork {
        try StationNetwork(
            information: informationFeed([near, mid, far, outer]),
            status: statusFeed(statuses),
            now: referenceNow
        )
    }

    // MARK: - Dock near a destination

    @Test func usualDockWithRoomIsKept() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "mid",
            in: try network([status("near", docks: 9), status("mid", docks: 25)])
        )
        #expect(result.usesUsualDock)
        #expect(result.selected?.id == "mid")
        #expect(result.summary == "Your usual dock has 25 docks open.")
    }

    @Test func fullUsualDockReroutesToNearestWithRoom() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "near",
            in: try network([status("near", docks: 0), status("mid", docks: 8), status("far", docks: 30)])
        )
        #expect(result.usualDockProblem == .full)
        #expect(result.selected?.id == "mid")
        #expect(result.summary.hasPrefix("Your usual dock is full. Go to Court and State, 8 docks, "))
        #expect(result.summary.hasSuffix(" from school."))
    }

    @Test func usualDockProblemsAreNamed() throws {
        let almostFull = DockFinderService.dock(near: school, usualStationID: "near", in: try network([status("near", docks: 1), status("mid", docks: 4)]))
        #expect(almostFull.usualDockProblem == .almostFull)

        let closed = DockFinderService.dock(near: school, usualStationID: "near", in: try network([status("near", docks: 9, returning: false), status("mid", docks: 4)]))
        #expect(closed.summary.hasPrefix("Your usual dock is closed."))
    }

    @Test func withoutUsualDockPicksNearestWithRoom() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: nil,
            in: try network([status("near", docks: 1), status("mid", docks: 5)])
        )
        #expect(result.usualDock == nil)
        #expect(result.selected?.id == "mid")
        #expect(result.summary.hasPrefix("Court and State has 5 docks open, "))
    }

    @Test func onlyLooksWithinWalkingDistanceOfTheDestination() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "near",
            in: try network([status("near", docks: 0), status("outer", docks: 40)])
        )
        #expect(result.selected == nil)
        #expect(result.summary == "Your usual dock is full. No docks with space near school.")
    }

    @Test func missingUsualDockIsIgnored() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "removed",
            in: try network([status("near", docks: 6)])
        )
        #expect(result.usualDock == nil)
        #expect(result.selected?.id == "near")
        #expect(result.summary == "Smith and Bergen has 6 docks open, right at school.")
    }

    // MARK: - Station check

    @Test func stationWithRoomReportsDocksAndBikes() throws {
        let network = try network([status("near", docks: 29, bikes: 4)])
        let result = DockFinderService.check(try #require(network.station(id: "near")), in: network)
        #expect(result.problem == nil)
        #expect(result.summary == "Smith and Bergen has 29 docks open and 4 bikes.")
        #expect(result.answer.station?.id == "near")
    }

    @Test func fullStationSuggestsANearbyAlternative() throws {
        let network = try network([status("near", docks: 0), status("mid", docks: 7), status("far", docks: 20)])
        let result = DockFinderService.check(try #require(network.station(id: "near")), in: network)
        #expect(result.problem == .full)
        #expect(result.alternative?.id == "mid")
        #expect(result.summary.hasPrefix("Smith and Bergen is full. Go to Court and State, 7 docks, "))
        #expect(result.answer.station?.id == "mid")
    }

    @Test func fullStationWithNothingNearby() throws {
        let network = try network([status("near", docks: 0), status("outer", docks: 20)])
        let result = DockFinderService.check(try #require(network.station(id: "near")), in: network)
        #expect(result.summary == "Smith and Bergen is full, and nothing nearby has space.")
        #expect(result.answer.station == nil)
    }

    @Test func stationsMatchBySpokenName() throws {
        let network = try network([status("near", docks: 3), status("mid", docks: 3)])
        #expect(network.bestMatch(for: "smith and bergen")?.id == "near")
        #expect(network.bestMatch(for: "court street and state street")?.id == "mid")
        #expect(network.bestMatch(for: "mid")?.id == "mid", "station IDs match exactly")
        #expect(network.bestMatch(for: "times square") == nil)
    }

    @Test func unknownStationNameThrows() async {
        let service = DockFinderService(
            location: StubLocation(result: .failure(.locationUnavailable)),
            feeds: StubFeeds(information: .success(informationFeed([near])), status: .success(statusFeed([status("near", docks: 3)]))),
            now: { referenceNow }
        )
        await #expect(throws: DockFinderError.stationNotFound("times square")) {
            try await service.checkStation("times square")
        }
    }

    // MARK: - Citywide

    @Test func citywideTotals() throws {
        let summary = try network([
            status("near", docks: 0, bikes: 20, ebikes: 3),
            status("mid", docks: 10, bikes: 5),
            status("far", docks: 0, bikes: 1, returning: false),
            status("outer", docks: 4, bikes: 0, installed: false),
        ]).summary
        #expect(summary.bikesAvailable == 26)
        #expect(summary.ebikesAvailable == 3)
        #expect(summary.openDocks == 14)
        #expect(summary.activeStations == 3)
        #expect(summary.fullStations == 1, "only installed stations accepting returns count as full")
        #expect(summary.summary.hasSuffix("citywide. 1 station is full."))
    }
}
