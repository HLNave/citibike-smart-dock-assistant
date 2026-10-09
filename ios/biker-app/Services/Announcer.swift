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

    private let synthesizer = AVSpeechSynthesizer()
    private var speechFinished: CheckedContinuation<Void, Never>?
    /// Identifies the current utterance, so a stale timeout can't end a newer one.
    private var utteranceID = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

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
            synthesizer.speak(AVSpeechUtterance(string: text))
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
