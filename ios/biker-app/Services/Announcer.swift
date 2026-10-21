//
//  Announcer.swift
//  Dock Finder
//
//  Speaks an arrival answer through whatever audio is connected (ducking
//  music or navigation the way Maps does) and posts it as a notification,
//  so it still reaches the rider if speech can't play. With AirPods and
//  Announce Notifications on, Siri also reads the notification aloud.
//  Also speaks the Action Button's answer (speakAnswer), one answer at a
//  time: a second press cuts the first answer short.
//

import AVFoundation
import Foundation
import UIKit
import UserNotifications

final class Announcer {
    /// Notification identifier for ride and place arrival alerts.
    nonisolated static let arrivalNotificationID = "ride-arrival"

    private let synthesizer: any SpeechSynthesizing
    private let audio: SpeechAudio
    /// Longest a spoken answer is waited for, in case speech never reports finishing.
    private let speechTimeout: Duration
    private let postRequest: (UNNotificationRequest) async -> Void

    /// What's being said now, and the caller waiting for it to finish.
    private var current: (ticket: Int, finished: CheckedContinuation<Void, Never>)?
    /// Bumped by every request to speak, so the newest one wins.
    private var latestTicket = 0

    init(
        synthesizer: any SpeechSynthesizing = SystemSpeechSynthesizer(),
        audio: SpeechAudio = .shared,
        speechTimeout: Duration = .seconds(30),
        postRequest: @escaping (UNNotificationRequest) async -> Void = { request in
            try? await UNUserNotificationCenter.current().add(request)
        }
    ) {
        self.synthesizer = synthesizer
        self.audio = audio
        self.speechTimeout = speechTimeout
        self.postRequest = postRequest
    }

    /// Returns once the answer has been spoken (or speech failed), so the
    /// caller can keep the app awake until then.
    /// Speaks first, then posts the notification: quietly when it was
    /// spoken (so Siri's Announce Notifications doesn't read it out over
    /// the app's voice, or get cut off by it), as an alert when it wasn't.
    func announce(_ text: String, title: String, notificationID: String = arrivalNotificationID) async {
        let spoken = await speak(text)
        await postNotification(text, title: title, identifier: notificationID, quietly: spoken)
    }

    /// Speaks an answer the rider just asked for (the Action Button). The
    /// notification is only a fallback here, posted if audio can't start,
    /// so AirPods with Announce Notifications on don't say it twice.
    func speakAnswer(_ text: String, title: String, notificationID: String) async {
        if await !speak(text) {
            await postNotification(text, title: title, identifier: notificationID)
        }
    }

    /// One answer at a time, and the newest wins: asking again (a second
    /// press of the Action Button) stops what's being said straight away
    /// and lets its caller return, then says the new answer. Returns
    /// `false` if audio couldn't start, so nothing was said.
    @discardableResult
    private func speak(_ text: String) async -> Bool {
        latestTicket += 1
        let ticket = latestTicket
        interrupt()
        // The notification still carries the answer if audio can't start.
        guard await audio.acquire() else { return false }
        defer { audio.release() }
        // A newer answer arrived while audio was starting; it speaks instead.
        guard ticket == latestTicket else { return true }
        await withCheckedContinuation { continuation in
            current = (ticket, continuation)
            synthesizer.speak(text) { [weak self] in self?.finish(ticket) }
            let timeout = speechTimeout
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(ticket)
            }
        }
        return true
    }

    /// Ends the wait for `ticket`, if it's still the one being said.
    private func finish(_ ticket: Int) {
        guard let current, current.ticket == ticket else { return }
        self.current = nil
        current.finished.resume()
    }

    /// Stops what's being said now and lets its caller return.
    private func interrupt() {
        guard let current else { return }
        self.current = nil
        synthesizer.stopSpeaking()
        current.finished.resume()
    }

    /// Asks to send notifications, once, and only while the app is on
    /// screen. From Siri or the background iOS can't show the prompt, and
    /// waiting for it held up "start a ride" until Siri gave up ("Something
    /// went wrong") even though the ride had started.
    static func requestNotificationPermission() async {
        guard UIApplication.shared.applicationState == .active else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func postNotification(_ text: String, title: String, identifier: String, quietly: Bool = false) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        // Already heard: shown without a sound, and not announced by Siri.
        // Otherwise it breaks through Focus when the app has the Time
        // Sensitive entitlement (else iOS treats it as a normal one).
        content.interruptionLevel = quietly ? .passive : .timeSensitive
        await postRequest(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

/// Speaks text in the app's voice (SpokenVoice). Abstracted for testing.
protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    /// Queues `text` after anything already being said, and calls `done`
    /// once when it has been said or stopped.
    func speak(_ text: String, done: @escaping () -> Void)
    /// Stops at once; everything queued reports done.
    func stopSpeaking()
}

/// An AVSpeechSynthesizer speaking SpokenVoice utterances.
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    /// Created on first use: setting one up loads the speech engine, which
    /// is slow and would otherwise hold up the first screen at launch.
    private var created: AVSpeechSynthesizer?
    /// Who to tell when each queued utterance is done. Holding the
    /// utterance keeps its identifier from being reused meanwhile.
    private var pending: [ObjectIdentifier: (utterance: AVSpeechUtterance, done: () -> Void)] = [:]

    private var synthesizer: AVSpeechSynthesizer {
        if let created { return created }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        created = synthesizer
        return synthesizer
    }

    var isSpeaking: Bool { created?.isSpeaking ?? false }

    func speak(_ text: String, done: @escaping () -> Void) {
        let utterance = SpokenVoice.utterance(text)
        pending[ObjectIdentifier(utterance)] = (utterance, done)
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        created?.stopSpeaking(at: .immediate)
    }

    private func finished(_ id: ObjectIdentifier) {
        pending.removeValue(forKey: id)?.done()
    }
}

extension SystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}

/// How Dock Finder sounds when it speaks on its own (ride alerts and
/// directions). Siri's replies use Siri's voice; for the app's own speech,
/// iOS doesn't hand out Siri's voice directly, so this picks the closest
/// one available: a Siri voice if the system lists one, otherwise the
/// best-quality male voice for the phone's language. Downloading an
/// "Enhanced" or "Premium" male voice in Settings › Accessibility ›
/// Spoken Content › Voices makes it sound better.
enum SpokenVoice {
    /// The default rate (0.5) sounds rushed for directions on a bike.
    static let rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.88

    static let voice: AVSpeechSynthesisVoice? = pickVoice(
        from: AVSpeechSynthesisVoice.speechVoices(),
        language: AVSpeechSynthesisVoice.currentLanguageCode()
    )

    static func utterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.2
        return utterance
    }

    /// Prefers, in order: male, a Siri voice, then Premium over Enhanced
    /// over the basic quality. Novelty voices never win.
    static func pickVoice(from voices: [AVSpeechSynthesisVoice], language: String) -> AVSpeechSynthesisVoice? {
        let exact = voices.filter { $0.language == language }
        let candidates = exact.isEmpty ? voices.filter { $0.language.hasPrefix(String(language.prefix(2))) } : exact
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var score = 0
            if voice.gender == .male { score += 100 }
            if voice.identifier.lowercased().contains("siri") { score += 50 }
            switch voice.quality {
            case .premium: score += 20
            case .enhanced: score += 10
            default: break
            }
            if voice.voiceTraits.contains(.isNoveltyVoice) { score -= 1_000 }
            return score
        }
        return candidates.max { score($0) < score($1) }
    }
}

/// Shows ride notifications even while Dock Finder is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// Turns audio on for spoken prompts (lowering music or navigation the way
/// Maps does) and back off once nobody is speaking. The ride alerts, the
/// Action Button's answer and directions each speak with their own
/// synthesizer on the one shared audio session, so each holds a claim
/// while it talks: audio goes off only when the last claim is released,
/// and one voice going quiet can't cut another off mid-sentence.
final class SpeechAudio {
    static let shared = SpeechAudio(session: SystemAudioSession())

    private let session: any AudioSessionSwitching
    /// Claims not yet released, including ones still waiting for audio to start.
    private(set) var claims = 0

    init(session: any AudioSessionSwitching) {
        self.session = session
    }

    /// Claims audio for speaking; `false` if it couldn't start (e.g.
    /// during a phone call), and then there's nothing to release. Each
    /// claim asks for audio again: that's harmless when it's already on,
    /// and picks it back up after an interruption.
    func acquire() async -> Bool {
        // Counted before waiting, so a release meanwhile can't turn audio
        // off underneath this claim.
        claims += 1
        if await session.activate() { return true }
        release()
        return false
    }

    /// Gives up a claim; the last one lets other audio come back to full volume.
    func release() {
        guard claims > 0 else { return }
        claims -= 1
        if claims == 0 { session.deactivate() }
    }
}

/// The phone's audio session. Abstracted for testing.
protocol AudioSessionSwitching {
    /// `false` if audio couldn't start.
    func activate() async -> Bool
    func deactivate()
}

/// Done on a background queue: iOS warns that the audio session can block
/// for a while, freezing the screen if it's called on the main thread.
/// The queue is serial, so an "off" and a following "on" always happen in
/// order.
nonisolated struct SystemAudioSession: AudioSessionSwitching {
    private static let queue = DispatchQueue(label: "DockFinder.speechAudio", qos: .userInitiated)

    func activate() async -> Bool {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    // Ducks other audio, but doesn't interrupt other spoken
                    // audio: that option also cut Siri off mid-sentence.
                    try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func deactivate() {
        Self.queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
