//
//  VoiceAsk.swift
//  Dock Finder
//
//  Ask Dock Finder by Voice: started by the Ask Dock Finder control. It
//  says "What do you need?", listens with on-device speech recognition
//  until the rider pauses, answers out loud, and for a dock offers "Want me
//  to direct you there?" and listens for yes or no. Same answers, savings
//  and usage events as asking through Siri, without depending on Siri to
//  recognize a phrase.
//

import AVFoundation
import Foundation
import Speech
import UIKit

final class VoiceAsk {
    static let shared = VoiceAsk()

    static let question = "What do you need?"
    /// Longest a question can take.
    private static let maxQuestion: Duration = .seconds(10)
    /// Longest wait for a yes or no.
    private static let maxReply: Duration = .seconds(5)
    /// Silence after speech that ends listening.
    private static let pauseToFinish: TimeInterval = 1.4
    /// Give up if nothing is said at all in this long.
    private static let waitForSpeech: TimeInterval = 5

    private let announcer = Announcer()
    private var isRunning = false
    private var startedActivity = false

    // MARK: - Permissions

    /// Both are needed to listen; they can only be asked for while the app
    /// is on screen, so the Siri screen has a button for it.
    static var hasPermissions: Bool {
        AVAudioApplication.shared.recordPermission == .granted
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestPermissions() async -> Bool {
        let microphone = await AVAudioApplication.requestRecordPermission()
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return microphone && speech == .authorized
    }

    // MARK: - Running

    /// Called by the control's intent. Shows the Live Activity iOS requires,
    /// and listens for the question while the intent is still running
    /// (that's when iOS allows the microphone from the Lock Screen). The
    /// answer is spoken afterwards in the background.
    func begin() async {
        // Logged first, so the sheet shows whether presses reach the app.
        Metrics.shared.log("voice_button_pressed", details: ["permissions": Self.hasPermissions ? "yes" : "no"])
        guard !isRunning else { return }
        isRunning = true
        startedActivity = false
        if !DockFinderLiveActivity.shared.isShowing {
            await DockFinderLiveActivity.shared.show(destination: "Dock Finder", state: .listening(Self.question))
            startedActivity = DockFinderLiveActivity.shared.isShowing
        }
        let question = await askQuestion()
        Task {
            await self.respond(to: question)
            self.isRunning = false
        }
    }

    /// "What do you need?", then what the rider says. `nil` without
    /// permission or if nothing was understood.
    private func askQuestion() async -> String? {
        guard Self.hasPermissions else { return nil }
        await announcer.speak(Self.question)
        return await listen(for: Self.maxQuestion)
    }

    private func respond(to question: String?) async {
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Ask by voice")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        guard Self.hasPermissions else {
            await finish(saying: "To ask by voice, open Dock Finder and allow the microphone and speech recognition on the Siri screen.")
            return
        }
        guard let question else {
            await finish(saying: "Sorry, I didn't catch that.")
            return
        }
        Metrics.shared.log("voice_question", details: ["text": question])

        let rideBefore = RideTracker.shared.currentRide
        let answer: DockAnswer
        do {
            answer = try await AssistantRouter.live().answer(question)
        } catch let error as DockFinderError {
            await finish(saying: String(localized: error.localizedStringResource))
            return
        } catch {
            await finish(saying: String(localized: DockFinderError.networkUnavailable.localizedStringResource))
            return
        }

        let here = LocationService.shared.lastKnownLocation
        Metrics.shared.log(
            "voice_answer",
            station: answer.station?.name,
            avoidedStation: answer.avoided?.name,
            location: here,
            details: ["question": question, "answer": answer.text]
        )
        SavingsStore.shared.record(answer, from: here, context: "voice_button")
        if answer.station != nil {
            SavingsStore.shared.recordHandsFree(context: "voice_button")
        }

        // A ride just started: offer guidance on arrival, as Siri does.
        if let ride = RideTracker.shared.currentRide, ride != rideBefore {
            await announcer.speak("\(answer.text) \(GuidanceSession.rideQuestion)")
            if VoiceReply.parse(await listen(for: Self.maxReply)) == .yes {
                RideTracker.shared.setGuidesToDock(true)
                await finish(saying: "Okay. When you're close, I'll guide you to the dock.")
            } else {
                await finish(saying: "Okay. I'll just tell you where to dock.")
            }
            return
        }

        // A dock: offer directions.
        let guidance = GuidanceSession.shared
        if let station = answer.station, guidance.station?.id != station.id {
            guidance.offer(station)
            await announcer.speak("\(answer.text) \(GuidanceSession.offerQuestion)")
            guard VoiceReply.parse(await listen(for: Self.maxReply)) == .yes else {
                await finish(saying: "Okay.", showing: answer)
                return
            }
            do {
                // Speaks the opening itself and takes over the Live Activity.
                _ = try await guidance.start(to: station, siriWillSay: nil)
                startedActivity = false
            } catch let error as DockFinderError {
                await finish(saying: String(localized: error.localizedStringResource), showing: answer)
            } catch {}
            return
        }

        await finish(saying: answer.text, showing: answer.station == nil ? nil : answer)
    }

    /// Says the last thing, and ends the listening Live Activity (leaving
    /// the answer on the Lock Screen for a minute) if this started it.
    private func finish(saying text: String, showing answer: DockAnswer? = nil) async {
        await announcer.speak(text)
        guard startedActivity, !GuidanceSession.shared.isActive, RideTracker.shared.currentRide == nil else { return }
        startedActivity = false
        if let answer {
            await DockFinderLiveActivity.shared.end(showing: .answer(answer), lingering: 60)
        } else {
            await DockFinderLiveActivity.shared.end()
        }
    }

    // MARK: - Listening

    /// Transcribes until the rider pauses, gives up if they say nothing,
    /// and stops at `limit` regardless. `nil` if nothing was understood.
    private func listen(for limit: Duration) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else { return nil }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0), block: Self.tap(feeding: request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return nil
        }

        let transcript = Transcript()
        let task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(updating: transcript))

        let started = Date.now
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !transcript.isFinal {
            try? await Task.sleep(for: .milliseconds(200))
            if transcript.text.isEmpty {
                if Date.now.timeIntervalSince(started) > Self.waitForSpeech { break }
            } else if Date.now.timeIntervalSince(transcript.lastChange) > Self.pauseToFinish {
                break
            }
        }

        engine.stop()
        input.removeTap(onBus: 0)
        request.endAudio()
        task.cancel()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Built outside the main actor: iOS calls it on its audio thread.
    private nonisolated static func tap(feeding request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Built outside the main actor: Speech calls it on its own queue.
    private nonisolated static func resultHandler(updating transcript: Transcript) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in transcript.update(text: text, isFinal: isFinal) }
        }
    }
}

/// What's been heard so far.
private final class Transcript {
    private(set) var text = ""
    private(set) var isFinal = false
    private(set) var lastChange = Date.now

    func update(text newText: String?, isFinal final: Bool) {
        if let newText, newText != text {
            text = newText
            lastChange = .now
        }
        if final { isFinal = true }
    }
}

/// The rider's answer to a yes-or-no question.
nonisolated enum VoiceReply: Equatable {
    case yes
    case no
    case unclear

    private static let noWords = ["no", "nope", "nah", "don't", "do not", "cancel", "stop", "never mind", "not now"]
    private static let yesWords = [
        "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "please", "go", "go ahead", "do it",
        "direct me", "take me", "guide me", "let's go", "absolutely", "definitely",
    ]

    static func parse(_ text: String?) -> VoiceReply {
        guard let text else { return .unclear }
        let words = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        let phrase = " " + words.joined(separator: " ") + " "
        func says(_ word: String) -> Bool { phrase.contains(" \(word) ") }
        if noWords.contains(where: says) { return .no }
        if yesWords.contains(where: says) { return .yes }
        return .unclear
    }
}
