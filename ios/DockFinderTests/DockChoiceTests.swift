//
//  DockChoiceTests.swift
//  DockFinderTests
//
//  Which dock near a destination gets recommended: walking along
//  Manhattan's street grid or Apple Maps' walking distances, and
//  preferring a nearly tied dock on the rider's way.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

struct StreetGridTests {
    let start = CLLocation(latitude: 40.7500, longitude: -73.9900)

    @Test func alongAnAvenueMatchesStraightLine() {
        let upTheAvenue = CLLocation(latitude: 40.753928, longitude: -73.987126) // ≈ 500 m along the avenues
        #expect(abs(StreetGrid.distance(from: start, to: upTheAvenue) - 500) < 2)
    }

    @Test func acrossTheGridIsLongerThanStraightLine() {
        let dueNorth = CLLocation(latitude: 40.754492, longitude: -73.9900) // 500 m due north, diagonal to the grid
        let grid = StreetGrid.distance(from: start, to: dueNorth)
        #expect(abs(grid - 680) < 5)
    }

    @Test func offTheGridIsStraightLine() {
        let brooklyn = CLLocation(latitude: 40.6861, longitude: -73.9906)
        let alsoBrooklyn = CLLocation(latitude: 40.6900, longitude: -73.9920)
        #expect(StreetGrid.distance(from: brooklyn, to: alsoBrooklyn) == brooklyn.distance(from: alsoBrooklyn))
    }

    @Test(arguments: [
        (40.7334, -73.9884), // East 14th St near Third Avenue
        (40.7377, -73.9997), // West 14th St & Seventh Avenue
        (40.7940, -73.9720), // Upper West Side
        (40.8680, -73.9200), // Inwood
    ])
    func onTheGrid(latitude: Double, longitude: Double) {
        #expect(StreetGrid.isOnGrid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }

    @Test(arguments: [
        (40.7334, -74.0037), // West Village
        (40.7075, -74.0110), // Financial District
        (40.6861, -73.9906), // Brooklyn
        (40.7440, -73.9480), // Long Island City
        (40.7440, -74.0300), // Hoboken
    ])
    func offTheGrid(latitude: Double, longitude: Double) {
        #expect(!StreetGrid.isOnGrid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }
}

/// Riding east on 14th St from Seventh Avenue to Palladium Hall. E 12 St &
/// 3 Ave is the closest walk (about 195 m on the grid); E 12 St & 4 Ave is
/// about 30 m more but on the way; Union Square is the shortest ride but
/// more than a block's extra walk.
struct OnTheWayDockTests {
    let third = info("third", "E 12 St & 3 Ave", 40.7322, -73.9880)
    let fourth = info("fourth", "E 12 St & 4 Ave", 40.7330, -73.9902)
    let union = info("union", "Union Sq E & E 15 St", 40.7356, -73.9912)
    let palladium = Destination(name: "Palladium", latitude: 40.7334, longitude: -73.9884)
    let rider = CLLocation(latitude: 40.7377, longitude: -73.9997)

    private func network(third thirdDocks: Int = 10, fourth fourthDocks: Int = 10, union unionDocks: Int = 10) throws -> StationNetwork {
        try StationNetwork(
            information: informationFeed([third, fourth, union]),
            status: statusFeed([status("third", docks: thirdDocks), status("fourth", docks: fourthDocks), status("union", docks: unionDocks)]),
            now: referenceNow
        )
    }

    @Test func withoutTheRiderLocationTheClosestWalkWins() throws {
        let result = DockFinderService.dock(near: palladium, usualStationID: nil, in: try network())
        #expect(result.selected?.id == "third")
    }

    @Test func aNearlyTiedDockOnTheWayWins() throws {
        let result = DockFinderService.dock(near: palladium, usualStationID: nil, from: rider, in: try network())
        #expect(result.selected?.id == "fourth")
    }

    @Test func aDockOnTheWayButMuchFartherToWalkLoses() throws {
        let result = DockFinderService.dock(near: palladium, usualStationID: nil, from: rider, in: try network(fourth: 0))
        #expect(result.selected?.id == "third")
    }

    @Test func comingFromTheEastKeepsTheClosestWalk() throws {
        let fromTheEast = CLLocation(latitude: 40.7300, longitude: -73.9800)
        let result = DockFinderService.dock(near: palladium, usualStationID: nil, from: fromTheEast, in: try network())
        #expect(result.selected?.id == "third")
    }

    @Test func theUsualDockStillWins() throws {
        let result = DockFinderService.dock(near: palladium, usualStationID: "third", from: rider, in: try network())
        #expect(result.usesUsualDock)
        #expect(result.selected?.id == "third")
    }

    // MARK: - Apple Maps walking distances

    @Test func mapsWalkingDistancesReplaceTheEstimate() throws {
        // Maps says E 12 St & 3 Ave is a long walk (say, no crossing there).
        let result = DockFinderService.dock(
            near: palladium, usualStationID: nil,
            walkingDistances: ["third": 400, "fourth": 220, "union": 500],
            in: try network()
        )
        #expect(result.selected?.id == "fourth")
    }

    @Test func aDockMapsDidntAnswerForKeepsItsEstimate() throws {
        // Only E 12 St & 4 Ave came back, longer than 3 Ave's ~195 m estimate.
        let result = DockFinderService.dock(
            near: palladium, usualStationID: nil,
            walkingDistances: ["fourth": 300],
            in: try network()
        )
        #expect(result.selected?.id == "third")
    }

    @Test func mapsDistancesStillLetTheDockOnTheWayWin() throws {
        let result = DockFinderService.dock(
            near: palladium, usualStationID: nil, from: rider,
            walkingDistances: ["third": 200, "fourth": 240, "union": 450],
            in: try network()
        )
        #expect(result.selected?.id == "fourth")
    }

    // MARK: - Service

    private func service(recent: CLLocation? = nil, walking: [String: CLLocationDistance] = [:]) -> DockFinderService {
        DockFinderService(
            location: StubLocation(result: .failure(.locationUnavailable), recent: recent),
            feeds: StubFeeds(
                information: .success(informationFeed([third, fourth, union])),
                status: .success(statusFeed([status("third", docks: 10), status("fourth", docks: 10), status("union", docks: 10)]))
            ),
            now: { referenceNow },
            walking: StubWalkingDistances(distances: walking)
        )
    }

    @Test func theServiceUsesARecentFix() async throws {
        #expect(try await service(recent: rider).findDock(near: palladium).selected?.id == "fourth")
    }

    @Test func theServiceUsesMapsWalkingDistances() async throws {
        let found = try await service(walking: ["third": 400, "fourth": 220]).findDock(near: palladium)
        #expect(found.selected?.id == "fourth")
    }

    @Test func theServiceKeepsTheUsualDockWhateverMapsSays() async throws {
        let found = try await service(walking: ["third": 400, "fourth": 220])
            .findDock(near: palladium, usualStationID: "third")
        #expect(found.usesUsualDock)
        #expect(found.selected?.id == "third")
    }
}

/// Answers with fixed walking distances, for the stations asked about.
struct StubWalkingDistances: WalkingDistanceProviding {
    var distances: [String: CLLocationDistance]

    func walkingDistances(
        to destination: CLLocation,
        from stations: [DockStation],
        timeLimit: Duration
    ) async -> [String: CLLocationDistance] {
        distances.filter { id, _ in stations.contains { $0.id == id } }
    }
}
