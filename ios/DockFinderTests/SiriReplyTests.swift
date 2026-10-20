//
//  SiriReplyTests.swift
//  DockFinderTests
//
//  What Siri says and starts after an answer, for each Directions setting.
//

import Foundation
import Testing
@testable import DockFinder

@MainActor
struct SiriReplyTests {
    private let dock = DockStation(
        id: "dock", name: "W 4 St & Mercer St", latitude: 40.729, longitude: -73.996,
        availableDocks: 8, straightLineDistance: 300, observedAt: nil
    )
    private let otherDock = DockStation(
        id: "other", name: "Mercer St & Bleecker St", latitude: 40.7271, longitude: -73.9965,
        availableDocks: 9, straightLineDistance: 500, observedAt: nil
    )
    private let school = Destination(name: "school", latitude: 40.7290, longitude: -73.9965)

    private var dockAnswer: DockAnswer {
        DockAnswer(text: "West 4th and Mercer has 8 docks open, 1,000 feet away.", station: dock)
    }

    private let rideAnswer = DockAnswer(text: "Got it. I'll tell you where to dock when you're about 0.3 miles from school.")

    /// Records Siri's questions; `says` is the rider's answer.
    private final class SiriSpy {
        var says: Bool
        private(set) var questions: [String] = []

        init(says: Bool) {
            self.says = says
        }

        func ask(_ question: String) async throws {
            questions.append(question)
            if !says { throw CancellationError() }
        }
    }

    private func replier(
        _ preference: DirectionsPreference,
        guidance: GuidanceSpy,
        rides: RideSpy,
        siri: SiriSpy
    ) -> SiriReplier {
        SiriReplier(guidance: guidance, rides: rides, preference: preference, confirm: siri.ask)
    }

    // MARK: Dock answers

    @Test func startRightAwayStartsDirectionsWithoutAsking() async throws {
        let guidance = GuidanceSpy(), siri = SiriSpy(says: false)
        let reply = try await replier(.always, guidance: guidance, rides: RideSpy(), siri: siri)
            .reply(to: dockAnswer, rideBefore: nil, checksForNewRide: false)
        #expect(siri.questions.isEmpty)
        #expect(guidance.started.map(\.id) == ["dock"])
        #expect(reply.dialog == "\(dockAnswer.text) Okay, directing you to West 4th and Mercer.")
        #expect(guidance.siriLines == [reply.dialog], "the app's voice waits for all of it")
        #expect(reply.value == dockAnswer.text)
    }

    @Test func startRightAwayStillSaysTheAnswerWhenDirectionsCantStart() async throws {
        let guidance = GuidanceSpy()
        guidance.startError = .routeUnavailable
        let reply = try await replier(.always, guidance: guidance, rides: RideSpy(), siri: SiriSpy(says: true))
            .reply(to: dockAnswer, rideBefore: nil, checksForNewRide: false)
        #expect(reply.dialog.hasPrefix(dockAnswer.text))
        #expect(reply.dialog.hasSuffix("Dock Finder couldn't work out a cycling route to that dock right now. Try again in a moment."))
        #expect(guidance.offered?.id == "dock", "so \"direct me\" can try again")
    }

    @Test func startRightAwayAsksWhenGuidingToAnotherDock() async throws {
        let guidance = GuidanceSpy(guidingTo: otherDock), siri = SiriSpy(says: false)
        let reply = try await replier(.always, guidance: guidance, rides: RideSpy(), siri: siri)
            .reply(to: dockAnswer, rideBefore: nil, checksForNewRide: false)
        #expect(siri.questions == ["\(dockAnswer.text) \(GuidanceSession.offerQuestion)"])
        #expect(guidance.started.isEmpty)
        #expect(guidance.station?.id == "other", "still guiding where it was")
        #expect(reply.dialog == "Okay.")
    }

    @Test func askMeAsksAndStartsOnYes() async throws {
        let guidance = GuidanceSpy(), siri = SiriSpy(says: true)
        let reply = try await replier(.ask, guidance: guidance, rides: RideSpy(), siri: siri)
            .reply(to: dockAnswer, rideBefore: nil, checksForNewRide: false)
        #expect(siri.questions == ["\(dockAnswer.text) \(GuidanceSession.offerQuestion)"])
        #expect(guidance.started.map(\.id) == ["dock"])
        #expect(reply.dialog == "Okay, directing you to West 4th and Mercer.")
    }

    @Test func dontOfferJustAnswersButRemembersTheDock() async throws {
        let guidance = GuidanceSpy(), siri = SiriSpy(says: true)
        let reply = try await replier(.never, guidance: guidance, rides: RideSpy(), siri: siri)
            .reply(to: dockAnswer, rideBefore: nil, checksForNewRide: false)
        #expect(siri.questions.isEmpty)
        #expect(guidance.started.isEmpty)
        #expect(guidance.offered?.id == "dock")
        #expect(reply == SiriReply(value: dockAnswer.text, dialog: dockAnswer.text))
    }

    // MARK: Rides

    @Test(arguments: [(DirectionsPreference.always, true), (.never, false)])
    func newRidesFollowTheSettingWithoutAsking(preference: DirectionsPreference, guides: Bool) async throws {
        let rides = RideSpy(currentRide: Ride(destination: school)), siri = SiriSpy(says: true)
        let reply = try await replier(preference, guidance: GuidanceSpy(), rides: rides, siri: siri)
            .reply(to: rideAnswer, rideBefore: nil, checksForNewRide: true)
        #expect(siri.questions.isEmpty)
        #expect(rides.currentRide?.guidesToDock == guides)
        #expect(reply.dialog == (guides ? "\(rideAnswer.text) When you're close, I'll guide you to the dock." : rideAnswer.text))
    }

    @Test func askMeAsksAboutTheRide() async throws {
        let rides = RideSpy(currentRide: Ride(destination: school)), siri = SiriSpy(says: false)
        let reply = try await replier(.ask, guidance: GuidanceSpy(), rides: rides, siri: siri)
            .reply(to: rideAnswer, rideBefore: nil, checksForNewRide: true)
        #expect(siri.questions == ["\(rideAnswer.text) \(GuidanceSession.rideQuestion)"])
        #expect(rides.currentRide?.guidesToDock == false)
        #expect(reply.dialog == "Okay. I'll just tell you where to dock.")
    }

    // MARK: Usage data

    /// Each question Siri asks is reported once, with the rider's reply,
    /// for the team's `siri_followup` rows. Answers that ask nothing report nothing.
    @Test(arguments: [
        (DirectionsPreference.ask, true, false, [SiriQuestion.directions], [true]),
        (.ask, false, false, [.directions], [false]),
        (.ask, true, true, [.rideGuidance], [true]),
        (.ask, false, true, [.rideGuidance], [false]),
        (.always, true, false, [], []),
        (.never, true, false, [], []),
    ])
    func repliesAreReported(
        preference: DirectionsPreference, says: Bool, ride: Bool,
        questions: [SiriQuestion], yes: [Bool]
    ) async throws {
        var reported: [(SiriQuestion, Bool)] = []
        let siri = SiriSpy(says: says)
        let replier = SiriReplier(
            guidance: GuidanceSpy(),
            rides: ride ? RideSpy(currentRide: Ride(destination: school)) : RideSpy(),
            preference: preference,
            confirm: siri.ask,
            replied: { question, declined in reported.append((question, declined == nil)) }
        )
        _ = try await replier.reply(to: ride ? rideAnswer : dockAnswer, rideBefore: nil, checksForNewRide: ride)
        #expect(reported.map(\.0) == questions)
        #expect(reported.map(\.1) == yes)
    }

    @Test func alreadyThereIsADockAnswerNotARide() async throws {
        // "Start a ride to school" from right by school answers with a dock,
        // and the ride from before is still the current one.
        let before = Ride(destination: school)
        let rides = RideSpy(currentRide: before), guidance = GuidanceSpy(), siri = SiriSpy(says: true)
        _ = try await replier(.always, guidance: guidance, rides: rides, siri: siri)
            .reply(to: dockAnswer, rideBefore: before, checksForNewRide: true)
        #expect(guidance.started.map(\.id) == ["dock"])
        #expect(rides.currentRide?.guidesToDock == false, "the old ride is left alone")
    }
}
