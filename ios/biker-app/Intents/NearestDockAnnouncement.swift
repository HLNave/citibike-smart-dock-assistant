//
//  NearestDockAnnouncement.swift
//  Dock Finder
//
//  What the Action Button does (SpeakNearestDockIntent): finds the
//  nearest dock with room, the same way Find Dock does, and says it in
//  the app's own voice. Outside Siri, iOS shows an intent's dialog
//  instead of speaking it and turns follow-up questions into text boxes,
//  so this never asks anything. It says one sentence and remembers the
//  dock, so "Ask Dock Finder to direct me" can follow up.
//

import CoreLocation
import Foundation

/// Says an answer out loud. Abstracted for testing.
protocol AnswerSpeaking: AnyObject {
    func speakAnswer(_ text: String, title: String, notificationID: String) async
}

extension Announcer: AnswerSpeaking {}

struct NearestDockAnnouncement {
    /// Title of the notification posted if the answer can't be spoken.
    static let title = "Nearest dock"
    /// That notification's identifier, so it never replaces a ride arrival alert.
    static let notificationID = "action-button"
    /// Said when a search fails with something other than a DockFinderError.
    static let fallbackError = "Dock Finder couldn't find a dock right now. Try again in a moment."

    var service: DockFinderService
    var speaker: any AnswerSpeaking
    var guidance: any GuidanceControlling
    var savings: SavingsStore
    var metrics: Metrics
    /// Where the rider was, for metrics and the savings estimate.
    var lastKnownLocation: () -> CLLocation?

    /// Kept for the life of the app, so speech isn't cut off when an
    /// intent's copy of this goes away.
    private static let announcer = Announcer()

    static var live: NearestDockAnnouncement {
        NearestDockAnnouncement(
            service: .live,
            speaker: announcer,
            guidance: GuidanceSession.shared,
            savings: .shared,
            metrics: .shared,
            lastKnownLocation: { LocationService.shared.lastKnownLocation }
        )
    }

    /// Finds the dock and says it, or says why it couldn't. Returns once
    /// speech has finished (so the app stays awake until then) with the
    /// sentence that was said.
    func run() async -> String {
        let answer: DockAnswer
        do {
            answer = try await service.findNearestDock().answer
        } catch {
            // The messages are written to be spoken (DockFinderError).
            let message = (error as? DockFinderError)?.errorDescription ?? Self.fallbackError
            await say(message)
            return message
        }

        let here = lastKnownLocation()
        // Same event as a Siri answer, so it counts toward the team's
        // Siri requests; `intent` tells them apart.
        metrics.log(
            "siri_answer",
            station: answer.station?.name,
            avoidedStation: answer.avoided?.name,
            location: here,
            details: [
                "intent": String(describing: SpeakNearestDockIntent.self),
                "answer": answer.text,
                "answered_by": answer.answeredBy.rawValue,
            ]
        )
        savings.record(answer, from: here, context: "action_button")
        if let station = answer.station {
            // Dock information by voice: the rider didn't take out their phone.
            savings.recordHandsFree(context: "action_button")
            guidance.offer(station, now: .now)
        }
        await say(answer.text)
        return answer.text
    }

    /// While directions are being given, the answer joins their voice's
    /// queue, so it waits for a turn prompt instead of talking over it.
    private func say(_ text: String) async {
        if guidance.isActive {
            await guidance.say(text)
        } else {
            await speaker.speakAnswer(text, title: Self.title, notificationID: Self.notificationID)
        }
    }
}
