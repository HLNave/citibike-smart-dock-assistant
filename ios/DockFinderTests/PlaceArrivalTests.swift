//
//  PlaceArrivalTests.swift
//  DockFinderTests
//
//  Alerts when biking up to a saved place without a ride: only on a bike,
//  not twice in an hour, and not on top of a ride or directions.
//

import Foundation
import Testing
@testable import DockFinder

struct PlaceArrivalRuleTests {
    typealias Sample = PlaceArrivalRules.ActivitySample

    private func ago(_ minutes: Double) -> Date {
        referenceNow.addingTimeInterval(-minutes * 60)
    }

    @Test func ridingUpCountsAsCycling() {
        let samples = [Sample(start: ago(40), cycling: false, confident: true), Sample(start: ago(18), cycling: true, confident: true)]
        #expect(PlaceArrivalRules.wasCycling(samples, now: referenceNow))
    }

    @Test func justGotOffTheBikeStillCounts() {
        let samples = [Sample(start: ago(4), cycling: true, confident: true), Sample(start: ago(1), cycling: false, confident: true)]
        #expect(PlaceArrivalRules.wasCycling(samples, now: referenceNow))
    }

    @Test func walkingAfterAnEarlierRideDoesnt() {
        let samples = [Sample(start: ago(50), cycling: true, confident: true), Sample(start: ago(30), cycling: false, confident: true)]
        #expect(!PlaceArrivalRules.wasCycling(samples, now: referenceNow))
    }

    @Test func lowConfidenceCyclingIsIgnored() {
        let samples = [Sample(start: ago(20), cycling: false, confident: true), Sample(start: ago(2), cycling: true, confident: false)]
        #expect(!PlaceArrivalRules.wasCycling(samples, now: referenceNow))
    }

    @Test func noActivityIsNotCycling() {
        #expect(!PlaceArrivalRules.wasCycling([], now: referenceNow))
    }

    private func shouldAlert(
        enabled: Bool = true,
        busy: Bool = false,
        lastAlert: Date? = nil,
        cycling: Bool? = true
    ) -> Bool {
        PlaceArrivalRules.shouldAlert(enabled: enabled, busyWithRideOrDirections: busy, lastAlert: lastAlert, wasCycling: cycling, now: referenceNow)
    }

    @Test func alertsWhenBikingUp() {
        #expect(shouldAlert())
    }

    @Test func skipsWalkingAndTransit() {
        #expect(!shouldAlert(cycling: false))
    }

    @Test func alertsWhenMotionAccessIsOff() {
        #expect(shouldAlert(cycling: nil))
    }

    @Test func onceAnHourPerPlace() {
        #expect(!shouldAlert(lastAlert: ago(20)))
        #expect(shouldAlert(lastAlert: ago(61)))
    }

    @Test func notWhenTurnedOffOrBusy() {
        #expect(!shouldAlert(enabled: false))
        #expect(!shouldAlert(busy: true))
    }
}

struct SavedPlaceArrivalSettingTests {
    @Test func placesSavedBeforeThisSettingAlertByDefault() throws {
        let place = SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as? [String: Any])
        json.removeValue(forKey: "arrivalAlerts")
        let decoded = try JSONDecoder().decode(SavedPlace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.arrivalAlerts)
    }

    @Test func turningItOffIsSaved() throws {
        var place = SavedPlace(name: "Gym", latitude: 0, longitude: 0)
        place.arrivalAlerts = false
        let decoded = try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(place))
        #expect(!decoded.arrivalAlerts)
    }
}
