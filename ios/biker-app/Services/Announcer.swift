//
//  Announcer.swift
//  Dock Finder
//
//  Speaks an arrival answer through whatever audio is connected (ducking
//  music or navigation the way Maps does) and posts it as a notification,
//  so it still reaches the rider if speech can't play. With AirPods and
//  Announce Notifications on, Siri also reads the notification aloud.
//

import AVFoundation
import Foundation
import UserNotifications

final class Announcer: NSObject {
    /// Longest a spoken answer is waited for, in case speech never reports finishing.
    private static let speechTimeout: Duration = .seconds(30)

    /// Created on first use: setting one up loads the speech engine, which
    /// is slow and would otherwise hold up the first screen at launch.
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private var speechFinished: CheckedContinuation<Void, Never>?
    /// Identifies the current utterance, so a stale timeout can't end a newer one.
    private var utteranceID = 0

    /// Returns once the answer has been spoken (or speech failed), so the
    /// caller can keep the app awake until then.
    func announce(_ text: String, title: String) async {
        await Self.postNotification(text, title: title)
        await speak(text)
    }

    private func speak(_ text: String) async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // The notification still carries the answer.
            return
        }
        utteranceID += 1
        let id = utteranceID
        await withCheckedContinuation { continuation in
            speechFinished = continuation
            synthesizer.speak(SpokenVoice.utterance(text))
            Task { [weak self] in
                try? await Task.sleep(for: Self.speechTimeout)
                if self?.utteranceID == id { self?.finishSpeaking() }
            }
        }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishSpeaking() {
        speechFinished?.resume()
        speechFinished = nil
    }

    static func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private static func postNotification(_ text: String, title: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        // Breaks through Focus when the app has the Time Sensitive entitlement;
        // otherwise iOS treats it as a normal notification.
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "ride-arrival", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension Announcer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
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
