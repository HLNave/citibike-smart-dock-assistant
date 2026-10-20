//
//  SiriReply.swift
//  Dock Finder
//
//  What Siri says after an answer, and what it starts: asking whether to
//  direct the rider or guide their ride, or (with the Directions setting)
//  doing either without asking. Siri's yes/no question is passed in, so
//  this runs in tests without Siri.
//

import Foundation

/// The yes/no questions Siri can ask after an answer, as the team's sheet
/// names them (`siri_followup`).
enum SiriQuestion: String {
    /// "Want me to direct you there?"
    case directions
    /// A new ride's "Want me to guide you to the dock when you're close?"
    case rideGuidance = "ride_guidance"
}

struct SiriReply: Equatable {
    /// What Shortcuts receives.
    let value: String
    /// What Siri says.
    let dialog: String
}

@MainActor
struct SiriReplier {
    var guidance: any GuidanceControlling
    var rides: any RideControlling
    var preference: DirectionsPreference
    /// Asks Siri's yes/no question. Throws for "no", or when Siri couldn't ask.
    var confirm: (String) async throws -> Void
    /// Told the rider's reply to each question asked: `nil` for yes, or
    /// what `confirm` threw.
    var replied: (SiriQuestion, (any Error)?) -> Void = { _, _ in }

    func reply(to answer: DockAnswer, rideBefore: Ride?, checksForNewRide: Bool) async throws -> SiriReply {
        let startedRide = checksForNewRide && rides.currentRide != nil && rides.currentRide != rideBefore
        if !startedRide, let station = answer.station {
            // For "direct me", whatever happens next.
            guidance.offer(station, now: .now)
        }
        let followUp = SiriFollowUp.after(
            answer,
            startedRide: startedRide,
            guidingToStationID: guidance.station?.id,
            preference: preference
        )

        switch followUp {
        case .none:
            return SiriReply(value: answer.text, dialog: answer.text)

        case .guideRide(let guides):
            rides.setGuidesToDock(guides)
            guard guides else { return SiriReply(value: answer.text, dialog: answer.text) }
            return SiriReply(value: answer.text, dialog: "\(answer.text) When you're close, I'll guide you to the dock.")

        case .askToGuideRide:
            do {
                try await confirm("\(answer.text) \(GuidanceSession.rideQuestion)")
            } catch {
                replied(.rideGuidance, error)
                return SiriReply(value: answer.text, dialog: "Okay. I'll just tell you where to dock.")
            }
            replied(.rideGuidance, nil)
            rides.setGuidesToDock(true)
            return SiriReply(value: answer.text, dialog: "Okay. When you're close, I'll guide you to the dock.")

        case .offerDirections(let station):
            do {
                try await confirm("\(answer.text) \(GuidanceSession.offerQuestion)")
            } catch {
                replied(.directions, error)
                // "No", or Siri couldn't ask. The answer was already spoken with
                // the question, so don't repeat it.
                return SiriReply(value: answer.text, dialog: "Okay.")
            }
            replied(.directions, nil)
            // Siri only confirms; the app's voice gives the directions once Siri
            // has finished, so the two don't talk over each other.
            let siriLine = guidance.siriConfirmation(for: station)
            let opening = try await guidance.start(to: station, siriWillSay: siriLine)
            let spoken = guidance.isActive ? siriLine : opening
            return SiriReply(value: spoken, dialog: spoken)

        case .startDirections(let station):
            // As if the rider had said yes, but Siri also says the answer,
            // so the app's voice waits for both.
            let siriLine = "\(answer.text) \(guidance.siriConfirmation(for: station))"
            do {
                let opening = try await guidance.start(to: station, siriWillSay: siriLine)
                return SiriReply(value: answer.text, dialog: guidance.isActive ? siriLine : "\(answer.text) \(opening)")
            } catch let error as DockFinderError {
                // Keep the answer even when directions can't start.
                return SiriReply(value: answer.text, dialog: "\(answer.text) \(String(localized: error.localizedStringResource))")
            }
        }
    }
}
