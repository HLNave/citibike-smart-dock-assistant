//
//  AnsweredByTests.swift
//  DockFinderTests
//
//  Which step answered a request: recorded as `answered_by` in usage data.
//

import Foundation
import Testing
@testable import DockFinder

private struct ModelStub: RequestParsing {
    var result: ParsedRequest?
    var answerSource: DockAnswer.Source { .onDeviceModel }
    func parse(_ text: String) async -> ParsedRequest? { result }
}

@MainActor
struct AnsweredByTests {
    private var allParsers: [any RequestParsing] {
        [
            KeywordRequestParser(),
            ShortAnswerParser(savedPlaces: [], service: testRouter().service),
            ModelStub(result: .citywide),
        ]
    }

    @Test func fixedActionsAreOnDevice() async throws {
        let answer = try await testRouter().handle(.station("court and state"))
        #expect(answer.answeredBy == .fixedAction)
        #expect(answer.answeredBy.rawValue == "on_device")
        #expect(answer.source == .onDevice)
    }

    @Test func phraseRules() async throws {
        let answer = try await testRouter(parsers: allParsers).answer("is court and state full?")
        #expect(answer.answeredBy.rawValue == "phrase_rules")
        #expect(answer.source == .onDevice)
    }

    @Test func shortAnswers() async throws {
        let answer = try await testRouter(parsers: allParsers).answer("Court and State")
        #expect(answer.text == "Court and State has 6 docks open and 2 bikes.")
        #expect(answer.answeredBy.rawValue == "short_answer")
        #expect(answer.source == .onDevice)
    }

    @Test func appleIntelligence() async throws {
        let answer = try await testRouter(parsers: allParsers).answer("what's the situation with bikes across nyc")
        #expect(answer.answeredBy.rawValue == "apple_intelligence")
        #expect(answer.source == .onDeviceModel)
    }

    @Test func server() async throws {
        let answer = try await testRouter(backend: StubBackend(reply: "Ask me about docks.")).answer("tell me a joke")
        #expect(answer.answeredBy.rawValue == "server")
        #expect(answer.source == .server)
    }

    @Test func markingKeepsTheSourceInStep() {
        var answer = DockAnswer(text: "x")
        answer.markAnswered(by: .appleIntelligence)
        #expect(answer.source == .onDeviceModel)
        answer.markAnswered(by: .shortAnswer)
        #expect(answer.source == .onDevice)
    }
}
