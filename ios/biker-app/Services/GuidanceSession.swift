//
//  GuidanceSession.swift
//  Dock Finder
//
//  Spoken turn-by-turn directions to a dock, with the phone locked. Starts
//  from Siri ("Want me to direct you there?" → "Yes"), the Direct Me
//  button, or a ride's arrival when the rider asked to be guided. It
//  follows live location the way RideTracker does, speaks each turn as it
//  comes up, re-routes when the rider leaves the route, and re-checks the
//  dock every minute, saying whether it still has room and heading
//  somewhere else if it filled up.
//

import AVFoundation
import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit

/// What the assistant needs from guidance. Abstracted for testing.
protocol GuidanceControlling: AnyObject {
    var isActive: Bool { get }
    /// The dock being guided to, while guiding.
    var station: DockStation? { get }
    /// Remembers a dock the rider was just told about, for "take me there".
    func offer(_ station: DockStation, now: Date)
    /// The dock the rider was last offered directions to, if recently.
    func recentOffer(now: Date) -> DockStation?
    /// Starts guiding. The app's voice gives every instruction, starting
    /// with the opening ("0.3 miles to West 4th and Mercer. Head north on
    /// 6th Avenue."), which is also returned. When Siri started it, pass
    /// the line Siri is about to say as `siriWillSay`; the app holds its
    /// own speech until Siri should be done, so the two never talk over
    /// each other. If the rider is already at the dock, guidance doesn't
    /// start and a short message comes back instead.
    func start(to station: DockStation, siriWillSay siriLine: String?) async throws -> String
    /// What Siri says when directions start: just a confirmation.
    func siriConfirmation(for station: DockStation) -> String
    func stop() async
    /// Says `text` in the directions voice, after any prompt already
    /// queued, and returns once it has been said. For answers given while
    /// guiding (the Action Button), so they never talk over a turn.
    func say(_ text: String) async
}

/// Cycling directions. Abstracted for testing.
nonisolated protocol RouteProviding: Sendable {
    func route(from origin: CLLocation, to station: DockStation) async throws -> GuidanceRoute
}

nonisolated struct MapKitRouteProvider: RouteProviding {
    func route(from origin: CLLocation, to station: DockStation) async throws -> GuidanceRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: origin, address: nil)
        request.destination = MKMapItem(location: station.location, address: nil)
        request.transportType = .cycling
        request.requestsAlternateRoutes = false

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DockFinderError.routeUnavailable
        }
        guard let route = response.routes.first else { throw DockFinderError.routeUnavailable }
        let legs = route.steps.map { step in
            (instruction: step.instructions, points: Self.coordinates(of: step.polyline))
        }
        return GuidanceRoute(station: station, legs: legs)
    }

    private static func coordinates(of polyline: MKPolyline) -> [GuidanceCoordinate] {
        let points = polyline.points()
        return (0..<polyline.pointCount).map { GuidanceCoordinate(points[$0].coordinate) }
    }
}

@Observable
final class GuidanceSession: GuidanceControlling {
    static let shared = GuidanceSession()

    /// Asked after any answer that names a dock.
    static let offerQuestion = "Want me to direct you there?"
    /// Asked when a ride starts.
    static let rideQuestion = "Want me to guide you to the dock when you're close?"
    /// Guidance that never arrives stops after this long.
    static let maxDuration: TimeInterval = 45 * 60
    /// "Take me there" works for this long after a dock was offered.
    static let offerLifetime: TimeInterval = 10 * 60
    /// How often the target dock's availability is re-checked (and said
    /// out loud) on the way.
    static let dockCheckInterval: TimeInterval = 60
    /// The dock is also checked once more when the rider gets this close.
    static let finalDockCheckDistance: CLLocationDistance = 400
    /// Minimum time between re-routes, so a bad GPS patch can't cause a storm.
    static let rerouteCooldown: TimeInterval = 20

    /// Where the rider is along the current route; `nil` when not guiding.
    private(set) var progress: GuidanceProgress?
    /// Open docks at the target as of the last check.
    private(set) var docksOpen: Int?
    /// What was said on arrival, shown in the app afterwards.
    private(set) var lastArrival: String?

    var isActive: Bool { progress != nil }
    var station: DockStation? { progress?.route.station }

    private let routes: any RouteProviding
    private let prompter: VoicePrompter
    @ObservationIgnored private var offered: (station: DockStation, date: Date)?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var lastDockCheck = Date.distantPast
    @ObservationIgnored private var checkedNearEnd = false
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Bumped each time tracking starts, so a finishing session can tell
    /// whether newer directions took over.
    @ObservationIgnored private var trackingGeneration = 0

    init(routes: any RouteProviding = MapKitRouteProvider(), prompter: VoicePrompter = VoicePrompter()) {
        self.routes = routes
        self.prompter = prompter
    }

    // MARK: - Offering

    /// Remembers a dock the rider was just told about, for "take me there".
    func offer(_ station: DockStation, now: Date = .now) {
        offered = (station, now)
    }

    func recentOffer(now: Date = .now) -> DockStation? {
        guard let offered, now.timeIntervalSince(offered.date) <= Self.offerLifetime else { return nil }
        return offered.station
    }

    // MARK: - Starting and stopping

    func siriConfirmation(for station: DockStation) -> String {
        var line = "Okay, directing you to \(station.spokenName)."
        if LocationService.shared.authorizationStatus != .authorizedAlways,
           UIApplication.shared.applicationState != .active {
            line += " To hear each turn with your phone locked, open Dock Finder and allow location access all the time."
        }
        return line
    }

    func start(to station: DockStation, siriWillSay siriLine: String?) async throws -> String {
        let here = try await LocationService.shared.currentLocation().location
        if here.distance(from: station.location) <= GuidanceProgress.arrivalRadius * 2 {
            return "\(Speech.sentence(station.spokenName)) is right here."
        }
        let route = try await routes.route(from: here, to: station)

        await stopTracking()
        var progress = GuidanceProgress(route: route)
        let opening = progress.opening()
        self.progress = progress
        docksOpen = station.availableDocks
        lastArrival = nil
        offered = nil
        startedAt = .now
        lastDockCheck = .now
        lastReroute = .now
        checkedNearEnd = false
        beginTracking()

        await DockFinderLiveActivity.shared.show(
            destination: station.spokenName,
            state: .guiding(progress, docksOpen: docksOpen)
        )

        if let siriLine {
            prompter.hold(for: VoicePrompter.speakingTime(of: siriLine))
        }
        prompter.say(opening)
        Metrics.shared.log(
            "directions_started",
            station: station.name,
            location: here,
            details: ["via": siriLine == nil ? "app" : "siri", "route_meters": String(Int(route.length))]
        )
        return opening
    }

    func stop() async {
        guard progress != nil else { return }
        Metrics.shared.log("directions_stopped", station: station?.name)
        progress = nil
        prompter.dropHeld()
        await stopTracking()
        await Self.handActivityBack()
    }

    func say(_ text: String) async {
        prompter.say(text)
        await prompter.waitUntilDone()
    }

    /// When directions end mid-ride, the Live Activity goes back to showing
    /// the ride instead of disappearing.
    private static func handActivityBack(showing finalState: GuidanceActivityAttributes.ContentState? = nil) async {
        if let ride = RideTracker.shared.currentRide {
            await DockFinderLiveActivity.shared.update(
                .riding(to: ride.destination.name, remaining: RideTracker.shared.distanceRemaining),
                force: true
            )
        } else {
            await DockFinderLiveActivity.shared.end(showing: finalState, lingering: finalState == nil ? 0 : 2 * 60)
        }
    }

    func dismissLastArrival() {
        lastArrival = nil
    }

    // MARK: - Tracking

    private func beginTracking() {
        trackingGeneration += 1
        serviceSession = CLServiceSession(authorization: .whenInUse)
        // With only While Using access, this keeps updates flowing once the
        // app leaves the screen. It can only start while the app is on
        // screen; with Always access it isn't needed.
        if UIApplication.shared.applicationState == .active {
            backgroundSession = CLBackgroundActivitySession()
        }

        tasks.append(Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, self.progress != nil else { return }
                    guard await self.handle(update.location) else { return }
                }
            } catch {}
        })

        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxDuration))
            guard !Task.isCancelled, let self else { return }
            await self.stop()
        })
    }

    private func stopTracking() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// Returns false once guidance is over.
    private func handle(_ location: CLLocation?) async -> Bool {
        guard var progress else { return false }
        guard let location else { return true }

        let events = progress.update(at: location)
        self.progress = progress
        for event in events {
            switch event {
            case .say(let text):
                prompter.say(text)
            case .arrived:
                await arrive()
                return false
            case .offRoute:
                await reroute(from: location)
            }
        }
        guard self.progress != nil else { return false }

        await checkDockIfDue(from: location)
        if let current = self.progress {
            await DockFinderLiveActivity.shared.update(.guiding(current, docksOpen: docksOpen))
        }
        return self.progress != nil
    }

    private func arrive() async {
        guard let station else { return }
        var text = "You've arrived at \(station.spokenName)"
        if let docksOpen { text += ", \(Speech.docksOpen(docksOpen))" }
        text += "."
        Metrics.shared.log("directions_arrived", station: station.name)
        progress = nil
        lastArrival = text

        // Keep running until the arrival has been spoken; stopping location
        // first would let iOS suspend the app mid-sentence.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Dock arrival")
        let generation = trackingGeneration
        prompter.say(text)
        await Self.handActivityBack(showing: .arrived(at: station, docksOpen: docksOpen))
        await prompter.waitUntilDone()
        // New directions may have started while this was being spoken;
        // don't stop their tracking.
        if trackingGeneration == generation {
            await stopTracking()
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
    }

    /// Recomputes the route from where the rider is, to the same dock or
    /// to `newStation`, and says the new first instruction. Returns false
    /// when no new route was set.
    @discardableResult
    private func reroute(from location: CLLocation, to newStation: DockStation? = nil, announcement: String = "Rerouting.") async -> Bool {
        guard let current = station else { return false }
        guard newStation != nil || Date.now.timeIntervalSince(lastReroute) >= Self.rerouteCooldown else { return false }
        lastReroute = .now
        guard let route = try? await routes.route(from: location, to: newStation ?? current),
              progress != nil
        else { return false }
        var fresh = GuidanceProgress(route: route)
        let next = fresh.opening()
        progress = fresh
        prompter.say("\(announcement) \(next)")
        // The new first turn (and dock), without waiting for the next fix.
        await DockFinderLiveActivity.shared.update(.guiding(fresh, docksOpen: docksOpen), force: true)
        if newStation == nil {
            Metrics.shared.log("directions_rerouted", station: current.name, location: location)
        }
        return true
    }

    /// Re-checks the dock every minute and once more near the end, says
    /// whether it still has room, and heads somewhere else if it filled up.
    private func checkDockIfDue(from location: CLLocation) async {
        guard let progress else { return }
        let nearEnd = progress.remaining <= Self.finalDockCheckDistance && !checkedNearEnd
        guard nearEnd || Date.now.timeIntervalSince(lastDockCheck) >= Self.dockCheckInterval else { return }
        lastDockCheck = .now
        if nearEnd { checkedNearEnd = true }

        let target = progress.route.station
        guard let network = try? await DockFinderService.live.loadNetwork(),
              station?.id == target.id
        else { return }

        switch DockCheckOutcome.check(target.id, in: network) {
        case .fine(let docks):
            prompter.say(DockCheckOutcome.statusLine(for: target.spokenName, docksOpen: docks, previously: docksOpen))
            docksOpen = docks
        case .switchTo(let alternative, let problem):
            let switched = await reroute(
                from: location,
                to: alternative,
                announcement: "\(Speech.sentence(target.spokenName)) \(problem.phrase) now. Heading to \(alternative.spokenName) instead, \(Speech.docksOpen(alternative.availableDocks))."
            )
            if switched {
                docksOpen = alternative.availableDocks
                checkedNearEnd = false
                // The dock filled up on the way: a full dock avoided.
                SavingsStore.shared.record(
                    DockAnswer(text: "", station: alternative, avoided: AvoidedDock(target, problem: problem)),
                    from: location,
                    context: "directions"
                )
            } else {
                docksOpen = network.station(id: target.id)?.openDocks
            }
        case .noAlternative(let problem, let docks):
            docksOpen = docks
            prompter.say("\(Speech.sentence(target.spokenName)) \(problem.phrase) now, and nothing nearby has space.")
        case .unknown:
            break
        }
    }
}

/// Speaks guidance prompts without blocking, one after another, lowering
/// music or other audio while it talks (the way Maps does).
final class VoicePrompter {
    private let synthesizer: any SpeechSynthesizing
    private let audio: SpeechAudio
    /// Whether this prompter holds a claim on audio (SpeechAudio); it
    /// holds one from its first prompt until it has nothing left to say.
    private var audioClaim = AudioClaim.none

    private enum AudioClaim {
        case none, claiming, held
    }

    private var heldUntil: ContinuousClock.Instant?
    private var held: [String] = []
    /// The latest prompt waiting for audio to start; each waits for the one
    /// before, so prompts are spoken in the order they were said.
    private var starting: Task<Void, Never>?

    init(synthesizer: any SpeechSynthesizing = SystemSpeechSynthesizer(), audio: SpeechAudio = .shared) {
        self.synthesizer = synthesizer
        self.audio = audio
    }

    /// Roughly how long Siri takes to say `text`, including the moment
    /// before it starts talking, with room to spare: starting early talks
    /// over the end of Siri's sentence.
    static func speakingTime(of text: String) -> Duration {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return .seconds(2.5 + Double(words) * 0.45)
    }

    /// Queues everything said for `duration`, then speaks it in order.
    /// Used while Siri is still talking.
    func hold(for duration: Duration) {
        let until = ContinuousClock.now + duration
        heldUntil = until
        Task { [weak self] in
            try? await Task.sleep(until: until, clock: .continuous)
            self?.release(heldUntil: until)
        }
    }

    /// Forgets anything queued by `hold`, e.g. when directions stop.
    func dropHeld() {
        heldUntil = nil
        held.removeAll()
    }

    private func release(heldUntil until: ContinuousClock.Instant) {
        guard heldUntil == until else { return }
        heldUntil = nil
        let queued = held
        held.removeAll()
        for text in queued {
            speak(text)
        }
    }

    func say(_ text: String) {
        if heldUntil != nil {
            held.append(text)
        } else {
            speak(text)
        }
    }

    private func speak(_ text: String) {
        let previous = starting
        starting = Task { [weak self] in
            await previous?.value
            guard let self, await self.claimAudio() else { return }
            self.synthesizer.speak(text) { [weak self] in self?.releaseAudioIfIdle() }
        }
    }

    /// Returns once everything queued has been spoken, or after `timeout`.
    func waitUntilDone(timeout: Duration = .seconds(20)) async {
        let deadline = ContinuousClock.now + timeout
        await starting?.value
        // Speaking starts asynchronously, so give it a moment to begin.
        try? await Task.sleep(for: .milliseconds(300))
        while synthesizer.isSpeaking, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// `false` if audio couldn't start, so the prompt is dropped.
    private func claimAudio() async -> Bool {
        if case .held = audioClaim { return true }
        audioClaim = .claiming
        let claimed = await audio.acquire()
        audioClaim = claimed ? .held : .none
        return claimed
    }

    private func releaseAudioIfIdle() {
        guard case .held = audioClaim, !synthesizer.isSpeaking else { return }
        audioClaim = .none
        audio.release()
    }
}
