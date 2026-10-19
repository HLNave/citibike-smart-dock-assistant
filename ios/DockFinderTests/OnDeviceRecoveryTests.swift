//
//  OnDeviceRecoveryTests.swift
//  DockFinderTests
//
//  The second try with Apple's on-device model when a place or station
//  isn't found, for Siri actions and typed questions alike.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

/// Rewrites from a fixed table and remembers what it was asked.
actor RewriterSpy: PlaceQueryRewriting {
    let rewrites: [String: String]
    private(set) var asked: [String] = []

    init(_ rewrites: [String: String] = [:]) {
        self.rewrites = rewrites
    }

    func rewrite(_ description: String) async -> String? {
        asked.append(description)
        return rewrites[description]
    }
}

/// Answers every question the same way, and remembers them.
actor ServerSpy: AssistantBackend {
    let reply: String
    private(set) var questions: [String] = []

    init(reply: String) {
        self.reply = reply
    }

    func ask(_ text: String, location: CLLocation?, sessionID: String) async throws -> String {
        questions.append(text)
        return reply
    }
}

private struct OfflinePlaces: PlaceSearching {
    func search(_ query: String) async throws -> [Destination] {
        throw DockFinderError.networkUnavailable
    }
}

// MARK: - Places

@MainActor
struct PlaceRecoveryTests {
    /// Next to Court & State, about 0.5 km from the rider.
    private let russAndDaughters = Destination(name: "Russ & Daughters", latitude: 40.6900, longitude: -73.9921)
    /// Lower Manhattan, far from the rider, so a ride isn't already there.
    private let farAway = Destination(name: "Russ & Daughters", latitude: 40.7223, longitude: -73.9883)

    private func router(
        places: [String: Destination],
        rewrites: [String: String],
        parsers: [any RequestParsing] = [KeywordRequestParser()],
        rides: RideSpy? = nil,
        backend: (any AssistantBackend)? = nil
    ) -> (AssistantRouter, RewriterSpy) {
        let spy = RewriterSpy(rewrites)
        var router = testRouter(parsers: parsers, places: StubPlaces(results: places), rides: rides, backend: backend)
        router.placeRewriter = spy
        return (router, spy)
    }

    @Test func siriPlaceTheMapDoesntKnowIsRewritten() async throws {
        let (router, spy) = router(
            places: ["russ & daughters": russAndDaughters],
            rewrites: ["that bagel place by stern": "russ & daughters"]
        )
        let answer = try await router.handle(.place("that bagel place by stern"))
        #expect(answer.station?.id == "mid")
        // Still in the rider's words.
        #expect(answer.text == "Court and State has 6 docks open, right at that bagel place by stern.")
        #expect(answer.answeredBy == .appleIntelligence)
        #expect(answer.source == .onDeviceModel)
        #expect(await spy.asked == ["that bagel place by stern"])
    }

    @Test func typedPlaceTheMapDoesntKnowIsRewritten() async throws {
        let backend = ServerSpy(reply: "from the server")
        let (router, _) = router(
            places: ["russ & daughters": russAndDaughters],
            rewrites: ["that bagel place by stern": "russ & daughters"],
            backend: backend
        )
        let answer = try await router.answer("find a dock near that bagel place by stern")
        #expect(answer.station?.id == "mid")
        #expect(answer.answeredBy.rawValue == "apple_intelligence")
        #expect(await backend.questions.isEmpty, "found on device, so no server")
    }

    @Test func ridesToAPlaceTheMapDoesntKnow() async throws {
        let rides = RideSpy()
        let (router, _) = router(
            places: ["russ & daughters": farAway],
            rewrites: ["the bagel place on houston": "russ & daughters"],
            rides: rides
        )
        let answer = try await router.handle(.startRide("to the bagel place on houston"))
        let ride = try #require(rides.started.first)
        #expect(ride.destination.name == "the bagel place on houston")
        #expect(ride.destination.latitude == farAway.latitude)
        #expect(answer.text.hasPrefix("Got it. I'll tell you where to dock"))
        #expect(answer.answeredBy == .appleIntelligence)
    }

    @Test func foundStraightAwayNeverAsksTheModel() async throws {
        let (router, spy) = router(places: ["union square": russAndDaughters], rewrites: ["union square": "x"])
        let answer = try await router.handle(.place("union square"))
        #expect(answer.answeredBy == .fixedAction)
        #expect(await spy.asked.isEmpty)
    }

    @Test func stillNotFoundNamesWhatTheRiderSaid() async {
        let (router, spy) = router(places: [:], rewrites: ["atlantis": "the lost city of atlantis"])
        await #expect(throws: DockFinderError.placeNotFound("atlantis")) {
            try await router.handle(.place("atlantis"))
        }
        #expect(await spy.asked == ["atlantis"])
    }

    @Test func noRewriteMeansNotFound() async {
        let (router, _) = router(places: [:], rewrites: [:])
        await #expect(throws: DockFinderError.placeNotFound("atlantis")) {
            try await router.answer("find a dock near atlantis")
        }
    }

    @Test func withARewriteThatFailsTheServerIsStillAskedIfThereIsOne() async throws {
        let backend = ServerSpy(reply: "Mercer and Bleecker has 29 docks open.")
        let (router, spy) = router(places: [:], rewrites: [:], backend: backend)
        let answer = try await router.answer("find a dock near that bagel place by stern")
        #expect(answer.source == .server)
        #expect(await spy.asked == ["that bagel place by stern"])
        #expect(await backend.questions.count == 1)
    }

    @Test func networkErrorsArentRewritten() async {
        let spy = RewriterSpy(["union square": "union square park"])
        var router = testRouter(places: OfflinePlaces())
        router.placeRewriter = spy
        await #expect(throws: DockFinderError.networkUnavailable) {
            try await router.handle(.place("union square"))
        }
        #expect(await spy.asked.isEmpty)
    }

    @Test func aRewriteThatChangesNothingIsntSearchedAgain() async throws {
        let spy = RewriterSpy(["atlantis": "Atlantis"])
        let counter = SearchCounter()
        await #expect(throws: DockFinderError.placeNotFound("atlantis")) {
            try await counter.search("atlantis", rewritingWith: spy)
        }
        #expect(await counter.queries == ["atlantis"])
    }

    @Test func withoutTheModelNothingIsRewritten() async {
        // On a simulator or iPhone without Apple Intelligence, the live
        // rewriter gives up before asking anything.
        if !OnDeviceModelParser.isAvailable {
            #expect(await OnDeviceModelPlaceRewriter().rewrite("that bagel place by stern") == nil)
        }
    }
}

/// Finds nothing, and remembers every search.
private actor SearchCounter: PlaceSearching {
    private(set) var queries: [String] = []

    func search(_ query: String) async throws -> [Destination] {
        queries.append(query)
        throw DockFinderError.placeNotFound(query)
    }
}
