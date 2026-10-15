//
//  DockFinderLiveActivity.swift
//  Dock Finder
//
//  Starts, updates and ends the Lock Screen / Dynamic Island Live Activity
//  for rides and dock guidance. One activity covers both: a ride shows its
//  distance to go, then turns into turn-by-turn guidance on arrival.
//
//  iOS only lets an app *start* a Live Activity while it's on screen or
//  running a LiveActivityIntent (every Dock Finder intent that can start a
//  ride or guidance is one). Updating and ending work from the background.
//

import ActivityKit
import CoreLocation
import Foundation

final class DockFinderLiveActivity {
    static let shared = DockFinderLiveActivity()

    typealias State = GuidanceActivityAttributes.ContentState

    private var activity: Activity<GuidanceActivityAttributes>?
    private var lastState: State?
    private var lastUpdate = Date.distantPast

    init() {
        // Picks up an activity still showing from before a relaunch.
        activity = Activity<GuidanceActivityAttributes>.activities.first { $0.activityState == .active }
    }

    /// True while a ride, directions or voice question activity is showing.
    var isShowing: Bool {
        activity?.activityState == .active
    }

    /// Shows `state`, starting an activity if none is running. Fails
    /// quietly when Live Activities are off or can't be started right now.
    func show(destination: String, state: State) async {
        if let activity, activity.activityState == .active {
            await update(state, force: true)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: GuidanceActivityAttributes(destinationName: destination),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastState = state
            lastUpdate = .now
        } catch {
            activity = nil
        }
    }

    /// Updates the running activity. Changes that only move a distance
    /// along are sent at most every `minInterval` seconds.
    func update(_ state: State, minInterval: TimeInterval = 5, force: Bool = false) async {
        guard let activity, state != lastState else { return }
        let sameStep = state.headline == lastState?.headline
            && state.dockName == lastState?.dockName
            && state.docksOpen == lastState?.docksOpen
        if !force, sameStep, Date.now.timeIntervalSince(lastUpdate) < minInterval { return }
        lastState = state
        lastUpdate = .now
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Ends the activity, optionally leaving `finalState` on the Lock Screen for
    /// `lingering` seconds.
    func end(showing finalState: State? = nil, lingering: TimeInterval = 0) async {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        let policy: ActivityUIDismissalPolicy = lingering > 0 ? .after(.now.addingTimeInterval(lingering)) : .immediate
        await activity.end(finalState.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    }
}

// MARK: - What each phase shows

extension GuidanceActivityAttributes.ContentState {
    nonisolated static func riding(to destination: String, remaining: CLLocationDistance?) -> Self {
        Self(
            phase: .riding,
            headline: "Riding to \(destination)",
            detail: remaining.map { "\(Speech.length($0)) to go" } ?? "You'll hear where to dock as you get close",
            dockName: nil,
            docksOpen: nil,
            symbol: "figure.outdoor.cycle"
        )
    }

    nonisolated static func guiding(_ progress: GuidanceProgress, docksOpen: Int?) -> Self {
        let instruction = progress.nextManeuver.map { Speech.instruction($0.instruction) } ?? "Head to the dock"
        let detail = progress.distanceToNextManeuver.map { "In \(Speech.length($0))" }
            ?? "\(Speech.length(progress.remaining)) to go"
        return Self(
            phase: .guiding,
            headline: instruction,
            detail: detail,
            dockName: progress.route.station.spokenName,
            docksOpen: docksOpen,
            symbol: maneuverSymbol(for: instruction)
        )
    }

    /// While Ask Dock Finder by Voice is listening for a question.
    nonisolated static func listening(_ prompt: String) -> Self {
        Self(
            phase: .listening,
            headline: "Listening…",
            detail: prompt,
            dockName: nil,
            docksOpen: nil,
            symbol: "waveform"
        )
    }

    nonisolated static func arrived(at station: DockStation, docksOpen: Int?) -> Self {
        Self(
            phase: .arrived,
            headline: "You've arrived",
            detail: station.spokenName,
            dockName: station.spokenName,
            docksOpen: docksOpen,
            symbol: "mappin.circle.fill"
        )
    }

    /// A ride's arrival answer, when the rider didn't ask for guidance.
    nonisolated static func answer(_ answer: DockAnswer) -> Self {
        Self(
            phase: .arrived,
            headline: answer.station.map { "Dock at \($0.spokenName)" } ?? "Where to dock",
            detail: answer.text,
            dockName: answer.station?.spokenName,
            docksOpen: answer.station?.availableDocks,
            symbol: "parkingsign.circle.fill"
        )
    }

    /// An arrow for the maneuver, from the wording of the instruction.
    nonisolated static func maneuverSymbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("u-turn") || text.contains("u turn") { return "arrow.uturn.down" }
        if text.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
        if text.contains("dock") || text.contains("arrive") { return "mappin.circle.fill" }
        let slight = text.contains("slight") || text.contains("bear") || text.contains("keep")
        if text.contains("left") { return slight ? "arrow.up.left" : "arrow.turn.up.left" }
        if text.contains("right") { return slight ? "arrow.up.right" : "arrow.turn.up.right" }
        return "arrow.up"
    }
}
