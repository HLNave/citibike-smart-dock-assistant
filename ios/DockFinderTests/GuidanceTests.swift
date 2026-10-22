//
//  GuidanceTests.swift
//  DockFinderTests
//
//  Turn-by-turn guidance to a dock: building the route, what gets said
//  where, re-routing, mid-ride dock checks, and the requests that start
//  and stop it.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

/// North on 6th Avenue for ≈ 300 m, then right onto Bleecker for ≈ 200 m
/// to the dock.
private let start = GuidanceCoordinate(latitude: 40.7300, longitude: -73.9950)
private let corner = GuidanceCoordinate(latitude: 40.7327, longitude: -73.9950)
private let dockPoint = GuidanceCoordinate(latitude: 40.7327, longitude: -73.9926)

private let dock = DockStation(
    id: "dock", name: "Bleecker St & Mercer St",
    latitude: dockPoint.latitude, longitude: dockPoint.longitude,
    availableDocks: 8, straightLineDistance: 0, observedAt: nil
)

private func testRoute(firstInstruction: String = "") -> GuidanceRoute {
    GuidanceRoute(station: dock, legs: [
        (instruction: firstInstruction, points: [start, corner]),
        (instruction: "Turn right onto Bleecker St", points: [corner, dockPoint]),
        (instruction: "The destination is on your left", points: [dockPoint]),
    ])
}

private func fix(_ latitude: Double, _ longitude: Double, accuracy: CLLocationAccuracy = 5, after seconds: TimeInterval = 0) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: referenceNow.addingTimeInterval(seconds)
    )
}

private func spoken(_ events: [GuidanceProgress.Event]) -> String? {
    guard events.count == 1, case .say(let text) = events[0] else { return nil }
    return text
}

struct GuidanceRouteTests {
    @Test func legsBecomeOnePathWithManeuverOffsets() {
        let route = testRoute()
        #expect(route.path == [start, corner, dockPoint])
        #expect(route.steps.map(\.instruction) == ["Turn right onto Bleecker St", "The destination is on your left"])
        #expect(abs(route.steps[0].offset - 300) < 5)
        #expect(route.steps[1].offset == route.length)
        #expect(route.steps[1].isArrival)
        #expect(!route.steps[0].isArrival)
        #expect(abs(route.length - 502) < 10)
    }
}

struct GuidanceProgressTests {
    @Test func announcesEachTurnAheadAndThenAtTheCorner() {
        var progress = GuidanceProgress(route: testRoute())

        #expect(progress.update(at: fix(40.7300, -73.9950)).isEmpty)              // 300 m out

        let ahead = spoken(progress.update(at: fix(40.7315, -73.9950)))            // ≈ 130 m out
        #expect(ahead?.hasPrefix("In ") == true)
        #expect(ahead?.hasSuffix(", turn right onto Bleecker Street.") == true)
        #expect(progress.update(at: fix(40.7316, -73.9950)).isEmpty)              // said once only

        #expect(progress.update(at: fix(40.7325, -73.9950)) == [.say("Turn right onto Bleecker Street.")])

        let final = spoken(progress.update(at: fix(40.7327, -73.9935)))           // ≈ 75 m from the dock
        #expect(final?.hasSuffix(", the dock is on your left.") == true)

        #expect(progress.update(at: fix(40.7327, -73.9928)) == [.arrived])         // ≈ 17 m away
    }

    @Test func reroutesOnlyAfterTwoFixesOffTheRoute() {
        var progress = GuidanceProgress(route: testRoute())
        let blocksAway = fix(40.7310, -73.9900)
        #expect(progress.update(at: blocksAway).isEmpty)
        #expect(progress.update(at: blocksAway) == [.offRoute])
    }

    @Test func oneStrayFixDoesntReroute() {
        var progress = GuidanceProgress(route: testRoute())
        #expect(progress.update(at: fix(40.7310, -73.9900)).isEmpty)
        #expect(progress.update(at: fix(40.7305, -73.9950)).isEmpty)
        #expect(progress.update(at: fix(40.7310, -73.9900)).isEmpty)
    }

    @Test func aRouteLoopingBackPastTheStartDoesntSkipAhead() {
        // East 100 m, north 80 m, west past the start, then south on a street
        // 30 m west of it to the dock: the last leg passes closer to a fix
        // near the start than the first street does.
        let a = GuidanceCoordinate(latitude: 40.7300, longitude: -73.9950)
        let b = GuidanceCoordinate(latitude: 40.7300, longitude: -73.993815)
        let c = GuidanceCoordinate(latitude: 40.730719, longitude: -73.993815)
        let d = GuidanceCoordinate(latitude: 40.730719, longitude: -73.995356)
        let e = GuidanceCoordinate(latitude: 40.729461, longitude: -73.995356)
        let loopDock = DockStation(
            id: "loop", name: "Mercer St & W 3 St", latitude: e.latitude, longitude: e.longitude,
            availableDocks: 8, straightLineDistance: 0, observedAt: nil
        )
        let route = GuidanceRoute(station: loopDock, legs: [
            (instruction: "", points: [a, b]),
            (instruction: "Turn left onto Greene St", points: [b, c]),
            (instruction: "Turn left onto W 4th St", points: [c, d]),
            (instruction: "Turn left onto Mercer St", points: [d, e]),
            (instruction: "The destination is on your right", points: [e]),
        ])
        var progress = GuidanceProgress(route: route)
        _ = progress.opening()
        _ = progress.update(at: fix(40.7300, -73.995237))   // 20 m west of the start
        #expect(progress.nextManeuver?.instruction == "Turn left onto Greene St")
        #expect(progress.along < 5)
    }

    @Test func showsWhatTheRiderIsDoingNowAboveTheNextTurn() {
        var progress = GuidanceProgress(route: testRoute())
        _ = progress.opening()
        #expect(progress.currentInstruction == "Head north")
        #expect(progress.nextManeuver?.instruction == "Turn right onto Bleecker St")
        _ = progress.update(at: fix(40.7300, -73.9950))
        _ = progress.update(at: fix(40.7315, -73.9950))
        _ = progress.update(at: fix(40.7325, -73.9950))                            // at the corner
        #expect(progress.currentInstruction == "On Bleecker Street")

        var started = GuidanceProgress(route: testRoute(firstInstruction: "Head north on 6th Ave"))
        _ = started.opening()
        #expect(started.currentInstruction == "Head north on 6th Avenue")
    }

    @Test(arguments: [
        ("Turn right onto Bleecker Street", "On Bleecker Street"),
        ("Slight left onto Broadway.", "On Broadway"),
        ("Turn left to stay on West 4th Street", "On West 4th Street"),
        ("Make a U-turn", "Make a U-turn"),
    ])
    func streetAfterATurn(instruction: String, expected: String) {
        #expect(GuidanceProgress.street(after: instruction) == expected)
    }

    @Test func aFixTooFarAheadDoesntAnnounceTheTurnEarly() {
        var progress = GuidanceProgress(route: testRoute())
        _ = progress.opening()
        #expect(progress.update(at: fix(40.7300, -73.9950)).isEmpty)                         // 300 m from the corner
        // One second later, a rough fix right at the corner: GPS error, not 280 m of riding.
        #expect(progress.update(at: fix(40.7325, -73.9950, accuracy: 40, after: 1)).isEmpty)
        #expect(progress.along < 30)
        #expect(progress.nextManeuver?.instruction == "Turn right onto Bleecker St")
        // Riding on normally, the turn still comes at the corner.
        #expect(spoken(progress.update(at: fix(40.7315, -73.9950, after: 20)))?.hasPrefix("In ") == true)
        #expect(progress.update(at: fix(40.7325, -73.9950, after: 35)) == [.say("Turn right onto Bleecker Street.")])
    }

    @Test func aRoughFixPastATurnSaysItInsteadOfSkippingIt() {
        var progress = GuidanceProgress(route: testRoute())
        _ = progress.opening()
        _ = progress.update(at: fix(40.7300, -73.9950))
        _ = progress.update(at: fix(40.7315, -73.9950, after: 20))                         // "In 400 feet…"
        // 30 m past the corner, on a 40 m-accurate fix.
        #expect(progress.update(at: fix(40.7327, -73.99465, accuracy: 40, after: 40)) == [.say("Turn right onto Bleecker Street.")])
    }

    @Test func theDockIsOnlyAnnouncedNearTheDock() {
        // Maps' last step can start a block or more before the dock.
        let route = GuidanceRoute(station: dock, legs: [
            (instruction: "", points: [start, corner]),
            (instruction: "The destination is on your left", points: [corner, dockPoint]),
        ])
        #expect(route.steps.last?.offset == route.length)
        var progress = GuidanceProgress(route: route)
        _ = progress.opening()
        _ = progress.update(at: fix(40.7300, -73.9950))
        // 150 m before the corner: the dock is still 350 m away.
        #expect(progress.update(at: fix(40.7314, -73.9950, after: 20)).isEmpty)
        // On the dock's street, 120 m out.
        #expect(spoken(progress.update(at: fix(40.7327, -73.99403, after: 60)))?.hasSuffix(", the dock is on your left.") == true)
    }

    @Test func aTurnIsntAnnouncedWhileTheRiderIsStillFarFromIt() {
        var progress = GuidanceProgress(route: testRoute())
        _ = progress.opening()
        _ = progress.update(at: fix(40.7300, -73.9950))
        // GPS drifting ahead while the rider waits at a light (speed 0):
        // the route position can't run ahead, so nothing is said.
        for second in 1...20 {
            let drifting = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 40.7300 + Double(second) * 0.00012, longitude: -73.9950),
                altitude: 0, horizontalAccuracy: 30, verticalAccuracy: 5, course: 0, speed: 0,
                timestamp: referenceNow.addingTimeInterval(Double(second))
            )
            #expect(progress.update(at: drifting).isEmpty)
        }
        #expect(progress.along < 60)
    }

    @Test func inaccurateFixesAreIgnored() {
        var progress = GuidanceProgress(route: testRoute())
        #expect(progress.update(at: fix(40.7325, -73.9950, accuracy: 120)).isEmpty)
        #expect(progress.update(at: fix(40.7327, -73.9928, accuracy: -1)).isEmpty)
    }

    @Test func openingSaysHowFarAndTheFirstTurn() {
        var progress = GuidanceProgress(route: testRoute())
        let opening = progress.opening()
        // No first instruction from Maps: the direction comes from the route.
        #expect(opening.contains(" to Bleecker and Mercer. Head north, then in "))
        #expect(opening.hasSuffix(", turn right onto Bleecker Street."))
    }

    @Test func openingSaysAnImmediateManeuverDirectly() {
        var progress = GuidanceProgress(route: testRoute(firstInstruction: "Head north on 6th Ave"))
        #expect(progress.opening().hasSuffix(" to Bleecker and Mercer. Head north on 6th Avenue."))
        // The next thing said is the turn, not the start again.
        let ahead = spoken(progress.update(at: fix(40.7315, -73.9950)))
        #expect(ahead?.hasSuffix(", turn right onto Bleecker Street.") == true)
    }

    @Test func aBareStartInstructionGetsADirection() {
        var progress = GuidanceProgress(route: testRoute(firstInstruction: "Start on 6th Ave"))
        #expect(progress.opening().hasSuffix(" to Bleecker and Mercer. Head north on 6th Avenue."))
    }

    @Test func startDirectionFromTheRoute() {
        #expect(testRoute().startHeading == "north")
        let eastbound = GuidanceRoute(station: dock, legs: [(instruction: "", points: [corner, dockPoint])])
        #expect(eastbound.startHeading == "east")
    }

    @Test(arguments: [
        (29.0, "north"),     // up a Manhattan avenue
        (119.0, "east"),     // along a Manhattan street, toward the East River
        (209.0, "south"),
        (299.0, "west"),
        (-10.0, "north"),
        (350.0, "north"),
    ])
    func compassPoints(bearing: Double, expected: String) {
        #expect(GuidanceRoute.compassPoint(bearing) == expected)
    }

    @Test(arguments: [
        ("Start on West 14th Street", "Head east on West 14th Street"),
        ("Proceed to the route", "Head east"),
        ("Continue on Broadway", "Head east on Broadway"),
        ("Head west on Bleecker Street", "Head west on Bleecker Street"),
        ("Turn left onto 7th Avenue", "Turn left onto 7th Avenue"),
    ])
    func headingIsAddedOnlyWhenMissing(instruction: String, expected: String) {
        #expect(GuidanceProgress.addingHeading("east", to: instruction) == expected)
    }

    @Test func aMissedTurnIsSkippedSilently() {
        var progress = GuidanceProgress(route: testRoute())
        // First fix is already past the corner, on Bleecker.
        let events = progress.update(at: fix(40.7327, -73.9945))
        #expect(!events.contains(.say("Turn right onto Bleecker Street.")))
        #expect(progress.nextManeuver?.isArrival == true)
    }
}

struct InstructionSpeechTests {
    @Test(arguments: [
        ("Turn left onto W 4th St", "Turn left onto West 4th Street"),
        ("Turn left onto E 13 St", "Turn left onto East 13th Street"),
        ("Turn right onto St Marks Pl", "Turn right onto Saint Marks Place"),
        ("Turn right onto St. Marks Pl.", "Turn right onto Saint Marks Place"),
        ("Bear left onto Lafayette St & Astor Pl", "Bear left onto Lafayette Street and Astor Place"),
        ("The destination is on your left", "The dock is on your left"),
        ("Arrive at Destination", "You'll reach the dock"),
        ("Head north on 6th Ave.", "Head north on 6th Avenue"),
    ])
    func instructionsAreSpeakable(raw: String, spoken: String) {
        #expect(Speech.instruction(raw) == spoken)
    }

    @Test func maneuverArrows() {
        typealias State = GuidanceActivityAttributes.ContentState
        #expect(State.maneuverSymbol(for: "Turn left onto Bleecker Street") == "arrow.turn.up.left")
        #expect(State.maneuverSymbol(for: "Slight right onto Broadway") == "arrow.up.right")
        #expect(State.maneuverSymbol(for: "The dock is on your left") == "mappin.circle.fill")
        #expect(State.maneuverSymbol(for: "Head north on 6th Avenue") == "arrow.up")
    }
}

struct DockCheckTests {
    let target = info("t", "Bleecker St & Mercer St", 40.7327, -73.9926)
    let nearby = info("a", "Mercer St & Bleecker St", 40.7330, -73.9930)

    private func network(target targetDocks: Int, nearby nearbyDocks: Int) throws -> StationNetwork {
        try StationNetwork(
            information: informationFeed([target, nearby]),
            status: statusFeed([status("t", docks: targetDocks), status("a", docks: nearbyDocks)]),
            now: referenceNow
        )
    }

    @Test func roomyDockStays() throws {
        #expect(DockCheckOutcome.check("t", in: try network(target: 6, nearby: 9)) == .fine(docksOpen: 6))
    }

    @Test func fullDockSwitchesToTheNearestWithRoom() throws {
        guard case .switchTo(let alternative, let problem) = DockCheckOutcome.check("t", in: try network(target: 0, nearby: 9)) else {
            Issue.record("expected a switch")
            return
        }
        #expect(alternative.id == "a")
        #expect(problem == .full)
    }

    @Test func fullEverywhereKeepsTheDock() throws {
        #expect(DockCheckOutcome.check("t", in: try network(target: 0, nearby: 1)) == .noAlternative(problem: .full, docksOpen: 0))
    }

    @Test func removedStation() throws {
        #expect(DockCheckOutcome.check("gone", in: try network(target: 6, nearby: 9)) == .unknown)
    }

    @Test(arguments: [
        (8, Int?.some(9), "West 4th and Mercer still has 8 docks open."),
        (4, Int?.some(4), "West 4th and Mercer still has 4 docks open."),
        (3, Int?.some(6), "West 4th and Mercer is filling up, 3 docks open."),
        (9, Int?.none, "West 4th and Mercer still has 9 docks open."),
    ])
    func statusIsSaidAfterEachCheck(docks: Int, previously: Int?, expected: String) {
        #expect(DockCheckOutcome.statusLine(for: "West 4th and Mercer", docksOpen: docks, previously: previously) == expected)
    }
}

struct GuidanceParsingTests {
    @Test(arguments: [
        ("take me there", ParsedRequest.directions),
        ("Direct me.", .directions),
        ("guide me to the dock", .directions),
        ("take me to the dock", .directions),
        ("yes, take me there", .directions),
        ("directions", .directions),
        ("get directions to it", .directions),
        ("stop directions", .stopDirections),
        ("Cancel directions please", .stopDirections),
        ("stop guiding me", .stopDirections),
        ("take me to union square", .startRide("union square")),
        ("direct me to school", .directionsTo("school")),
        ("Guide me to Union Square", .directionsTo("union square")),
        ("give me directions to the flatiron", .directionsTo("the flatiron")),
        ("directions to my office", .directionsTo("my office")),
    ])
    func directionRequests(text: String, expected: ParsedRequest) {
        #expect(KeywordRequestParser.parse(text) == expected)
    }
}

@MainActor
struct GuidanceRouterTests {
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)

    // `rides` defaults to nil rather than `RideSpy()`: default arguments
    // aren't evaluated on the main actor, and RideSpy's init is.
    private func router(
        _ guidance: GuidanceSpy,
        rides: RideSpy? = nil,
        store: SavedPlacesStore? = nil,
        parsers: [any RequestParsing] = [KeywordRequestParser()]
    ) -> AssistantRouter {
        let rides = rides ?? RideSpy()
        let store = store ?? testStore()
        let fix = LocationFix(location: userLocation, isApproximate: false)
        return AssistantRouter(
            service: DockFinderService(
                location: StubLocation(result: .success(fix)),
                feeds: StubFeeds(information: .success(informationFeed([near])), status: .success(statusFeed([status("near", docks: 5)]))),
                now: { referenceNow }
            ),
            placeSearch: StubPlaces(),
            store: store,
            rides: rides,
            parsers: parsers,
            backend: nil,
            location: StubLocation(result: .success(fix)),
            sessionID: "app-test",
            guidance: guidance
        )
    }

    @Test func takeMeThereGoesToTheDockJustOffered() async throws {
        let guidance = GuidanceSpy(offered: dock)
        let answer = try await router(guidance).answer("take me there")
        #expect(guidance.started.map(\.id) == ["dock"])
        // Siri only confirms; the app's voice gives the directions.
        #expect(answer.text == "Okay, directing you to Bleecker and Mercer.")
    }

    @Test func takeMeThereWithoutAnOfferGoesToTheNearestDock() async throws {
        let guidance = GuidanceSpy()
        _ = try await router(guidance).answer("direct me")
        #expect(guidance.started.map(\.id) == ["near"])
    }

    @Test func directMeToASavedPlaceGoesToItsDock() async throws {
        let guidance = GuidanceSpy(offered: dock)
        let school = SavedPlace(name: "School", latitude: near.latitude, longitude: near.longitude)
        let answer = try await router(guidance, store: testStore([school])).answer("direct me to school")
        // Not the dock offered earlier, and not the nearest to the rider: school's.
        #expect(guidance.started.map(\.id) == ["near"])
        #expect(answer.text == "Okay, directing you to Smith and Bergen.")
    }

    @Test func aVagueModelReadingDoesntOverrideAClearRule() async throws {
        let guidance = GuidanceSpy(offered: dock)
        let school = SavedPlace(name: "School", latitude: near.latitude, longitude: near.longitude)
        // The model heard only "direct me"; the rules caught "to school".
        let model = ModelReadingStub(reading: .directions)
        _ = try await router(guidance, store: testStore([school]), parsers: [model, KeywordRequestParser()])
            .answer("direct me to school")
        #expect(guidance.started.map(\.id) == ["near"])
    }

    @Test func aSpecificModelReadingIsUsed() async throws {
        let guidance = GuidanceSpy(offered: dock)
        let school = SavedPlace(name: "School", latitude: near.latitude, longitude: near.longitude)
        let model = ModelReadingStub(reading: .directionsTo("school"))
        _ = try await router(guidance, store: testStore([school]), parsers: [model, KeywordRequestParser()])
            .answer("how do I get to a dock by class")
        #expect(guidance.started.map(\.id) == ["near"])
    }

    @Test func stopDirections() async throws {
        let guidance = GuidanceSpy(isActive: true)
        let answer = try await router(guidance).answer("stop directions")
        #expect(guidance.stopCount == 1)
        #expect(answer.text == AssistantRouter.stoppedDirections)
    }

    @Test func stopDirectionsBeforeArrivalTurnsOffRideGuidance() async throws {
        let school = Destination(name: "school", latitude: 40.7290, longitude: -73.9965)
        let rides = RideSpy(currentRide: Ride(destination: school, guidesToDock: true))
        let answer = try await router(GuidanceSpy(), rides: rides).answer("stop directions")
        #expect(rides.currentRide?.guidesToDock == false)
        #expect(answer.text == "Okay. On this ride, I'll just tell you where to dock.")
    }

    @Test func endMyRideAlsoStopsDirections() async throws {
        let guidance = GuidanceSpy(isActive: true)
        let answer = try await router(guidance).answer("end my ride")
        #expect(guidance.stopCount == 1)
        #expect(answer.text == AssistantRouter.stoppedDirections)
    }
}

struct RideGuidanceTests {
    @Test func ridesSavedBeforeGuidanceStillLoad() throws {
        let ride = Ride(destination: Destination(name: "school", latitude: 40.7290, longitude: -73.9965), startedAt: referenceNow)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ride)) as? [String: Any])
        json.removeValue(forKey: "guidesToDock")
        let decoded = try JSONDecoder().decode(Ride.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == ride)
        #expect(!decoded.guidesToDock)
    }
}

/// Stands in for Apple's model: always reads the request as `reading`.
private struct ModelReadingStub: RequestParsing {
    let reading: ParsedRequest?
    var answerSource: DockAnswer.Source { .onDeviceModel }
    func parse(_ text: String) async -> ParsedRequest? { reading }
}
