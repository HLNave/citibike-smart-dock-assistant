//
//  GuidanceActivityAttributes.swift
//  Dock Finder
//
//  The Live Activity on the Lock Screen and in the Dynamic Island, during a
//  ride and while guiding the rider to a dock. Compiled into both the app
//  (which starts and updates it) and the widget extension (which draws it).
//

import ActivityKit
import Foundation

nonisolated struct GuidanceActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            /// On a ride, before the arrival alert.
            case riding
            /// Turn-by-turn directions to a dock.
            case guiding
            /// At the dock, or the ride's arrival answer when not guiding.
            case arrived
            /// Ask Dock Finder by Voice is listening for a question.
            case listening
        }

        var phase: Phase
        /// "Turn left onto Bleecker Street", "Riding to school".
        var headline: String
        /// "In 500 feet", "0.8 miles to go".
        var detail: String
        /// The dock being guided to, as it's spoken: "West 4th and Mercer".
        var dockName: String?
        var docksOpen: Int?
        /// SF Symbol for the next maneuver or phase.
        var symbol: String
    }

    /// Where the rider is heading: a saved place, a searched place, or the dock.
    var destinationName: String
}
