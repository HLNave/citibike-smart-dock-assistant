//
//  SavingsTests.swift
//  DockFinderTests
//
//  Time and money saved by skipping full docks, which answers count, and
//  usage data only leaving the phone with the rider's consent.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

/// A rider 400 m south of a full dock; the dock with room is 200 m east of it.
private let rider = CLLocation(latitude: 40.7300, longitude: -73.9950)
private let fullDock = CLLocation(latitude: 40.733604, longitude: -73.9950)
private let roomyDock = CLLocation(latitude: 40.733604, longitude: -73.99263)

struct SavingsModelTests {
    @Test func detourIsTheExtraRidePlusFindingItFull() {
        // Without: 400 + 200 m. With: ≈ 447 m straight there. Extra ≈ 153 m.
        let minutes = SavingsModel.minutesSaved(from: rider, avoided: fullDock, chosen: roomyDock)
        #expect(minutes > 2.1 && minutes < 2.5)
    }

    @Test func withoutAStartingPointOnlyTheRideOnCounts() {
        let minutes = SavingsModel.minutesSaved(from: nil, avoided: fullDock, chosen: roomyDock)
        #expect(minutes > 2.3 && minutes < 2.8)
    }

    @Test func oneDetourIsCappedAtFifteenMinutes() {
        let farAway = CLLocation(latitude: 40.80, longitude: -73.90)
        #expect(SavingsModel.minutesSaved(from: rider, avoided: farAway, chosen: roomyDock) == SavingsModel.maxMinutesPerEvent)
    }

    @Test func typicalCommuterMonth() {
        // 50 rides × 1 hands-free minute, plus 5 full docks × 5 minutes.
        #expect(abs(SavingsModel.typicalFullDockMinutes - 25) < 0.001)
        #expect(abs(SavingsModel.typicalHandsFreeMinutes - 50) < 0.001)
        #expect(abs(SavingsModel.typicalMonthlyMinutes - 75) < 0.001)
        #expect(abs(SavingsModel.dollars(forMinutes: SavingsModel.typicalMonthlyMinutes) - 20.25) < 0.001)
    }
}

@MainActor
struct SavingsStoreTests {
    private let chosen = DockStation(
        id: "room", name: "Mercer St & Bleecker St",
        latitude: roomyDock.coordinate.latitude, longitude: roomyDock.coordinate.longitude,
        availableDocks: 8, straightLineDistance: 0, observedAt: nil
    )
    private let avoided = AvoidedDock(
        id: "full", name: "Bleecker St & Crosby St",
        latitude: fullDock.coordinate.latitude, longitude: fullDock.coordinate.longitude,
        problem: .full
    )

    private func store() -> SavingsStore {
        SavingsStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!, metrics: nil)
    }

    @Test func aRedirectIsCountedOnce() {
        let savings = store()
        let answer = DockAnswer(text: "", station: chosen, avoided: avoided)
        #expect(savings.record(answer, from: rider, context: "siri", now: referenceNow) != nil)
        #expect(savings.record(answer, from: rider, context: "app", now: referenceNow.addingTimeInterval(10 * 60)) == nil)
        #expect(savings.record(answer, from: rider, context: "siri", now: referenceNow.addingTimeInterval(45 * 60)) != nil)
        #expect(savings.allTime.fullDocksAvoided == 2)
    }

    @Test func answersThatDidntAvoidAFullDockDontCount() {
        let savings = store()
        #expect(savings.record(DockAnswer(text: "", station: chosen), from: rider, context: "siri") == nil)
        #expect(savings.record(DockAnswer(text: "", avoided: avoided), from: rider, context: "siri") == nil)
        #expect(savings.events.isEmpty)
    }

    @Test func savingsAreKept() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        SavingsStore(defaults: defaults, metrics: nil)
            .record(DockAnswer(text: "", station: chosen, avoided: avoided), from: rider, context: "siri")
        #expect(SavingsStore(defaults: defaults, metrics: nil).events.count == 1)
    }

    @Test func voiceAnswersCloseTogetherAreOneHandsFreeCheck() {
        let savings = store()
        #expect(savings.recordHandsFree(context: "siri", now: referenceNow) != nil)
        // "Yes, direct me" right after the Siri answer: same check.
        #expect(savings.recordHandsFree(context: "directions", now: referenceNow.addingTimeInterval(60)) == nil)
        #expect(savings.recordHandsFree(context: "ride_arrival", now: referenceNow.addingTimeInterval(20 * 60)) != nil)
        #expect(savings.allTime.handsFreeChecks == 2)
        #expect(savings.hasMeasuredSavings)
    }

    @Test func handsFreeChecksAddToTimeAndMoney() {
        let checks = [HandsFreeCheck(id: UUID(), date: referenceNow, context: "siri"),
                      HandsFreeCheck(id: UUID(), date: referenceNow, context: "ride_arrival")]
        let event = SavingsEvent(id: UUID(), date: referenceNow, avoided: avoided, chosenID: "room", chosenName: "x", minutes: 3, context: "siri")
        let summary = SavingsSummary.of([event], handsFree: checks)
        #expect(summary.fullDockMinutes == 3)
        #expect(summary.handsFreeMinutes == 2)
        #expect(summary.minutes == 5)
        #expect(abs(summary.dollars - 1.35) < 0.001)
    }

    @Test func monthlySummaryOnlyCountsThisMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        func event(_ date: Date, _ minutes: Double) -> SavingsEvent {
            SavingsEvent(id: UUID(), date: date, avoided: avoided, chosenID: "room", chosenName: "x", minutes: minutes, context: "siri")
        }
        let events = [event(lastMonth, 5), event(now, 3), event(now, 2)]
        let month = SavingsSummary.of(events, since: SavingsSummary.startOfMonth(containing: now, calendar: calendar))
        #expect(month.fullDocksAvoided == 2)
        #expect(month.minutes == 5)
        #expect(SavingsSummary.of(events).minutes == 10)
    }
}

struct AvoidedDockDetectionTests {
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)

    private func network(near nearDocks: Int, mid midDocks: Int) throws -> StationNetwork {
        try StationNetwork(
            information: informationFeed([near, mid]),
            status: statusFeed([status("near", docks: nearDocks), status("mid", docks: midDocks)]),
            now: referenceNow
        )
    }

    @Test func fullUsualDockIsAvoided() throws {
        let school = Destination(name: "school", latitude: 40.6861, longitude: -73.9906)
        let result = DockFinderService.dock(near: school, usualStationID: "near", in: try network(near: 0, mid: 8))
        #expect(result.answer.avoided?.id == "near")
        #expect(result.answer.avoided?.problem == "is full")
    }

    @Test func roomyUsualDockAvoidsNothing() throws {
        let school = Destination(name: "school", latitude: 40.6861, longitude: -73.9906)
        let result = DockFinderService.dock(near: school, usualStationID: "near", in: try network(near: 6, mid: 8))
        #expect(result.answer.avoided == nil)
    }

    @Test func withoutAUsualDockTheNearestFullOneIsAvoided() throws {
        let school = Destination(name: "school", latitude: 40.6861, longitude: -73.9906)
        let result = DockFinderService.dock(near: school, usualStationID: nil, in: try network(near: 0, mid: 8))
        #expect(result.selected?.id == "mid")
        #expect(result.answer.avoided?.id == "near")
    }

    @Test func aFullStationCheckWithAnAlternativeIsAvoided() throws {
        let network = try network(near: 0, mid: 8)
        let result = DockFinderService.check(try #require(network.station(id: "near")), in: network)
        #expect(result.answer.avoided?.id == "near")
        #expect(result.answer.station?.id == "mid")
    }
}

@MainActor
struct UsageSharingTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID())")!
    }

    @Test func nothingIsQueuedWithoutConsent() {
        let defaults = defaults()
        let metrics = Metrics(defaults: defaults, endpoint: nil)
        metrics.log("ride_started", location: nil)
        #expect(metrics.queuedCount == 0)

        UsageSharing.set(.declined, in: defaults)
        metrics.log("ride_started", location: nil)
        #expect(metrics.queuedCount == 0)

        UsageSharing.set(.granted, in: defaults)
        metrics.log("ride_started", location: nil)
        #expect(metrics.queuedCount == 1)

        metrics.discardQueued()
        #expect(metrics.queuedCount == 0)
    }

    @Test func sentEventsLeaveTheQueueAndFailedOnesStay() async {
        let defaults = defaults()
        UsageSharing.set(.granted, in: defaults)
        let url = URL(string: "https://script.google.com/macros/s/test/exec")!
        let ok: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let failing: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { _ in throw URLError(.notConnectedToInternet) }

        let offline = Metrics(defaults: defaults, endpoint: url, send: failing)
        offline.log("app_launch", location: nil)
        await offline.flush()
        #expect(offline.queuedCount == 1)

        // Next launch, back online: the queued event is sent.
        let online = Metrics(defaults: defaults, endpoint: url, send: ok)
        #expect(online.queuedCount == 1)
        await online.flush()
        #expect(online.queuedCount == 0)
    }

    @Test func aNameIsOptionalAndTidied() {
        let defaults = defaults()
        #expect(UsageSharing.name(in: defaults) == nil)
        UsageSharing.setName("  Dustin ", in: defaults)
        #expect(UsageSharing.name(in: defaults) == "Dustin")
        UsageSharing.setName("   ", in: defaults)
        #expect(UsageSharing.name(in: defaults) == nil)
    }

    @Test func openingAgainSoonIsTheSameVisit() {
        let defaults = defaults()
        UsageSharing.set(.granted, in: defaults)
        let metrics = Metrics(defaults: defaults, endpoint: nil)
        metrics.logOpened(now: referenceNow)
        metrics.logOpened(now: referenceNow.addingTimeInterval(60))
        #expect(metrics.queuedCount == 1)
        metrics.logOpened(now: referenceNow.addingTimeInterval(Metrics.sameVisit + 1))
        #expect(metrics.queuedCount == 2)
    }

    @Test(arguments: [
        ("script.google.com/macros/s/abc/exec", "https://script.google.com/macros/s/abc/exec"),
        ("https://script.google.com/macros/s/abc/exec", "https://script.google.com/macros/s/abc/exec"),
    ])
    func sheetAddress(value: String, expected: String) {
        #expect(Metrics.endpoint(from: value)?.absoluteString == expected)
    }

    @Test(arguments: ["", "  ", "$(DOCKFINDER_METRICS_URL)"])
    func noSheetAddressMeansNothingIsSent(value: String) {
        #expect(Metrics.endpoint(from: value) == nil)
    }
}
