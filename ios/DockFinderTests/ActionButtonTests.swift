//
//  ActionButtonTests.swift
//  DockFinderTests
//
//  One press of the Action Button: the nearest dock with room is said out
//  loud, offered for "direct me", and counted, and nothing is ever asked.
//

import AppIntents
import CoreLocation
import Foundation
import Testing
@testable import DockFinder

@MainActor
struct ActionButtonTests {
    private let here = LocationFix(location: userLocation, isApproximate: false)
    // Distances from `userLocation`: near ≈ 0 m, mid ≈ 450 m.
    private let stations = [
        info("near", "Smith St & Bergen St", 40.6861, -73.9906),
        info("mid", "Court St & State St", 40.6900, -73.9920),
    ]

    private struct Harness {
        let announcement: NearestDockAnnouncement
        let speaker: SpeakerSpy
        let guidance: GuidanceSpy
        let savings: SavingsStore
        let metrics: Metrics
        /// Keeps the defaults suite alive for the test; deleted afterwards.
        let defaults: TemporaryDefaults
    }

    private func harness(
        location: Result<LocationFix, DockFinderError>? = nil,
        statuses: [StationStatus] = [status("near", docks: 4), status("mid", docks: 2)],
        status statusResult: Result<GBFSFeed<StationStatusPayload>, DockFinderError>? = nil
    ) -> Harness {
        let temporary = TemporaryDefaults()
        let defaults = temporary.defaults
        UsageSharing.set(.granted, in: defaults)
        let service = DockFinderService(
            location: StubLocation(result: location ?? .success(here)),
            feeds: StubFeeds(
                information: .success(informationFeed(stations)),
                status: statusResult ?? .success(statusFeed(statuses))
            ),
            now: { referenceNow }
        )
        let speaker = SpeakerSpy()
        let guidance = GuidanceSpy()
        let savings = SavingsStore(defaults: defaults)
        let metrics = Metrics(defaults: defaults, endpoint: nil)
        let announcement = NearestDockAnnouncement(
            service: service,
            speaker: speaker,
            guidance: guidance,
            savings: savings,
            metrics: metrics,
            lastKnownLocation: { userLocation }
        )
        return Harness(
            announcement: announcement,
            speaker: speaker,
            guidance: guidance,
            savings: savings,
            metrics: metrics,
            defaults: temporary
        )
    }

    @Test func speaksExactlyTheNearestDockAnswer() async throws {
        let h = harness()
        let expected = try await h.announcement.service.findNearestDock().answer.text

        let said = await h.announcement.run()

        #expect(said == expected)
        #expect(h.speaker.spoken == [expected])
        // One sentence of facts, never a question.
        #expect(!said.contains("?"))
    }

    @Test func itsFallbackNotificationHasItsOwnIdentifier() async {
        let h = harness()
        _ = await h.announcement.run()
        #expect(h.speaker.notificationIDs == ["action-button"])
    }

    /// While directions are being given, the answer waits its turn in the
    /// directions voice instead of talking over a turn prompt.
    @Test func duringDirectionsTheAnswerJoinsTheDirectionsVoice() async {
        let h = harness()
        h.guidance.isActive = true
        let said = await h.announcement.run()
        #expect(h.guidance.said == [said])
        #expect(h.speaker.spoken.isEmpty)
    }

    @Test func duringDirectionsAnErrorJoinsTheDirectionsVoiceToo() async {
        let h = harness(status: .failure(.networkUnavailable))
        h.guidance.isActive = true
        let said = await h.announcement.run()
        #expect(said == DockFinderError.networkUnavailable.errorDescription)
        #expect(h.guidance.said == [said])
        #expect(h.speaker.spoken.isEmpty)
    }

    @Test func offersTheDockForDirectMe() async {
        let h = harness()
        _ = await h.announcement.run()
        #expect(h.guidance.offered?.id == "near")
        #expect(h.guidance.started.isEmpty)
    }

    @Test func skipsAFullNearestDockTheWayFindDockDoes() async {
        let h = harness(statuses: [status("near", docks: 0), status("mid", docks: 6)])
        let said = await h.announcement.run()
        #expect(h.speaker.spoken == [said])
        #expect(h.guidance.offered?.id == "mid")
        // Steering away from the full dock counts toward savings.
        #expect(h.savings.events.map(\.context) == ["action_button"])
    }

    @Test func countsAsAHandsFreeVoiceAnswer() async {
        let h = harness()
        _ = await h.announcement.run()
        #expect(h.savings.handsFree.map(\.context) == ["action_button"])
        #expect(h.metrics.queuedCount == 1)
    }

    @Test func speaksTheMessageWhenLocationIsOff() async {
        let h = harness(location: .failure(.locationPermissionDenied))
        let said = await h.announcement.run()
        #expect(said == DockFinderError.locationPermissionDenied.errorDescription)
        #expect(h.speaker.spoken == [said])
        #expect(h.guidance.offered == nil)
        #expect(h.savings.handsFree.isEmpty)
        // Logged as a failed request (siri_failed), not an answer.
        #expect(h.metrics.queuedCount == 1)
    }

    @Test func speaksTheMessageWhenOffline() async {
        let h = harness(status: .failure(.networkUnavailable))
        let said = await h.announcement.run()
        #expect(said == DockFinderError.networkUnavailable.errorDescription)
        #expect(h.speaker.spoken == [said])
    }

    @Test func speaksTheMessageWhenNoDockHasRoom() async {
        let h = harness(statuses: [status("near", docks: 0), status("mid", docks: 1)])
        let said = await h.announcement.run()
        #expect(said == DockFinderError.noAvailableDocks.errorDescription)
        #expect(h.speaker.spoken == [said])
        #expect(h.guidance.offered == nil)
    }

    /// Outside Siri, any question an intent asks becomes a text box, so the
    /// Action Button's intent has nothing to ask for.
    @Test func theIntentHasNoParametersToAskFor() {
        #expect(Mirror(reflecting: SpeakNearestDockIntent()).children.isEmpty)
        #expect(SpeakNearestDockIntent.supportedModes == .background)
        // Works locked: no unlock prompt from the Action Button or Lock Screen.
        #expect(SpeakNearestDockIntent.authenticationPolicy == .alwaysAllowed)
    }

    /// Listed as an action (so Shortcuts and the Action Button can run it)
    /// but not as a Siri phrase: iOS allows only ten, and they're for
    /// "Ask Dock Finder …" requests.
    @Test func isAnActionButNotASiriPhrase() throws {
        let url = try #require(
            Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents")
        )
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try #require(json["actions"] as? [String: Any])
        let shortcuts = try #require(json["autoShortcuts"] as? [[String: Any]])
        #expect(actions.keys.contains("SpeakNearestDockIntent"))
        #expect(!shortcuts.contains { $0["actionIdentifier"] as? String == "SpeakNearestDockIntent" })
    }
}
