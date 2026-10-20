//
//  AskIntentTests.swift
//  DockFinderTests
//
//  "Ask Dock Finder a question": what Siri's answer is built from.
//

import Foundation
import Testing
@testable import DockFinder

@MainActor
struct AskIntentTests {
    private var parsers: [any RequestParsing] {
        [KeywordRequestParser(), ShortAnswerParser(savedPlaces: [], service: testRouter().service)]
    }

    @Test func understoodRequestsAreAnsweredOnDevice() async throws {
        let answer = try await AskDockFinderIntent.answer("Is Court and State full?", with: testRouter(parsers: parsers))
        #expect(answer.text == "Court and State has 6 docks open and 2 bikes.")
        #expect(answer.station?.id == "mid", "names a dock, so the Directions setting applies")
        #expect(answer.answeredBy == .phraseRules)
    }

    @Test func aStationNameOnItsOwnWorks() async throws {
        let answer = try await AskDockFinderIntent.answer("court and state", with: testRouter(parsers: parsers))
        #expect(answer.answeredBy == .shortAnswer)
    }

    @Test(arguments: ["tell me a joke", "", "   "])
    func otherwiseTheHelpText(spoken: String) async throws {
        let answer = try await AskDockFinderIntent.answer(spoken, with: testRouter(parsers: parsers))
        #expect(answer.text == AssistantRouter.helpText)
        #expect(answer.station == nil)
    }

    @Test func silenceIsNeverSentToAServer() async throws {
        let server = ServerSpy(reply: "from the server")
        let answer = try await AskDockFinderIntent.answer(" ", with: testRouter(backend: server))
        #expect(answer.text == AssistantRouter.helpText)
        #expect(await server.questions.isEmpty)
    }

    @Test func ridesCanStartHere() async throws {
        let rides = RideSpy()
        let places = StubPlaces(results: ["union square": Destination(name: "Union Square", latitude: 40.7359, longitude: -73.9911)])
        let answer = try await AskDockFinderIntent.answer("start a ride to union square", with: testRouter(places: places, rides: rides))
        #expect(rides.started.count == 1)
        #expect(answer.text.hasPrefix("Got it."))
    }
}
