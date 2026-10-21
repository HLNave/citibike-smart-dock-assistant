//
//  DirectionsPreferenceTests.swift
//  DockFinderTests
//
//  The Directions setting, and what Siri does after an answer because of it.
//

import Foundation
import Testing
@testable import DockFinder

/// A class, so each test's defaults are deleted when it ends.
final class DirectionsPreferenceTests {
    private var suites: [TemporaryDefaults] = []

    private func defaults() -> UserDefaults {
        let suite = TemporaryDefaults()
        suites.append(suite)
        return suite.defaults
    }

    @Test func asksUntilChangedAndIsKept() {
        let defaults = defaults()
        #expect(DirectionsPreference.current(in: defaults) == .ask)
        DirectionsPreference.set(.always, in: defaults)
        #expect(DirectionsPreference.current(in: defaults) == .always)
        defaults.set("sometimes", forKey: DirectionsPreference.key)
        #expect(DirectionsPreference.current(in: defaults) == .ask, "an unknown value falls back to asking")
    }

    @Test func rideSwitchFollowsTheSetting() {
        let defaults = defaults()
        #expect(DirectionsPreference.rideSwitchDefault(in: defaults), "on at first, as before")
        DirectionsPreference.rememberRideSwitch(false, in: defaults)
        #expect(!DirectionsPreference.rideSwitchDefault(in: defaults))

        DirectionsPreference.set(.always, in: defaults)
        #expect(DirectionsPreference.rideSwitchDefault(in: defaults))
        DirectionsPreference.set(.never, in: defaults)
        #expect(!DirectionsPreference.rideSwitchDefault(in: defaults))
    }

    @Test func onlyAskMeRemembersTheRideSwitch() {
        let defaults = defaults()
        DirectionsPreference.set(.never, in: defaults)
        DirectionsPreference.rememberRideSwitch(true, in: defaults)
        DirectionsPreference.set(.ask, in: defaults)
        #expect(DirectionsPreference.rideSwitchDefault(in: defaults), "still the first-time default")

        DirectionsPreference.rememberRideSwitch(false, in: defaults)
        DirectionsPreference.set(.always, in: defaults)
        DirectionsPreference.rememberRideSwitch(true, in: defaults)
        DirectionsPreference.set(.ask, in: defaults)
        #expect(!DirectionsPreference.rideSwitchDefault(in: defaults), "Ask Me's last choice survives a detour")
    }

    @Test func everyOptionHasWords() {
        for option in DirectionsPreference.allCases {
            #expect(!option.title.isEmpty)
            #expect(!option.explanation.isEmpty)
        }
    }
}

struct SiriFollowUpTests {
    private let station = DockStation(
        id: "dock", name: "W 4 St & Mercer St", latitude: 40.729, longitude: -73.996,
        availableDocks: 8, straightLineDistance: 300, observedAt: nil
    )

    private var dockAnswer: DockAnswer {
        DockAnswer(text: "West 4th and Mercer has 8 docks open, 1,000 feet away.", station: station)
    }

    @Test func dockAnswers() {
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: nil, preference: .ask) == .offerDirections(station))
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: nil, preference: .always) == .startDirections(station))
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: nil, preference: .never) == .none)
    }

    @Test(arguments: DirectionsPreference.allCases)
    func nothingToOfferWithoutADock(preference: DirectionsPreference) {
        let citywide = DockAnswer(text: "35,393 bikes and 30,882 open docks citywide. 243 stations are full.")
        #expect(SiriFollowUp.after(citywide, startedRide: false, guidingToStationID: nil, preference: preference) == .none)
    }

    @Test(arguments: DirectionsPreference.allCases)
    func alreadyGuidingThereIsntOfferedAgain(preference: DirectionsPreference) {
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: "dock", preference: preference) == .alreadyGuiding)
    }

    @Test func newRides() {
        let started = DockAnswer(text: "Got it. I'll tell you where to dock when you're about 0.3 miles from school.")
        #expect(SiriFollowUp.after(started, startedRide: true, guidingToStationID: nil, preference: .ask) == .askToGuideRide)
        #expect(SiriFollowUp.after(started, startedRide: true, guidingToStationID: nil, preference: .always) == .guideRide(true))
        #expect(SiriFollowUp.after(started, startedRide: true, guidingToStationID: nil, preference: .never) == .guideRide(false))
    }

    @Test func startRightAwayAsksWhenGuidingToAnotherDock() {
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: "other", preference: .always) == .offerDirections(station))
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: "other", preference: .ask) == .offerDirections(station))
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: "other", preference: .never) == .none)
    }

    @Test func rideRequestsAnsweredRightAwayAreDockAnswers() {
        // "Start a ride to school" when already there answers with a dock instead.
        #expect(SiriFollowUp.after(dockAnswer, startedRide: false, guidingToStationID: nil, preference: .always) == .startDirections(station))
    }
}
