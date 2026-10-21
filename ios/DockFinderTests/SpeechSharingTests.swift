//
//  SpeechSharingTests.swift
//  DockFinderTests
//
//  Several voices share one audio session: ride alerts and the Action
//  Button (Announcer) and directions (VoicePrompter). Audio stays on until
//  the last of them is done, and a second Action Button press cuts the
//  first answer short instead of tangling the two.
//

import Foundation
import Testing
import UserNotifications
@testable import DockFinder

@MainActor
final class AudioSessionSpy: AudioSessionSwitching {
    /// "on" for each activation asked for, "off" for each deactivation.
    private(set) var events: [String] = []
    var activates = true

    var offCount: Int { events.filter { $0 == "off" }.count }

    func activate() async -> Bool {
        events.append("on")
        return activates
    }

    func deactivate() {
        events.append("off")
    }
}

/// Never finishes on its own; the test says when each utterance is done.
@MainActor
final class SynthesizerSpy: SpeechSynthesizing {
    /// Everything ever asked to be said, in order.
    private(set) var said: [String] = []
    private(set) var stopCount = 0
    private var queued: [(text: String, done: () -> Void)] = []

    var isSpeaking: Bool { !queued.isEmpty }
    var current: String? { queued.first?.text }

    func speak(_ text: String, done: @escaping () -> Void) {
        said.append(text)
        queued.append((text, done))
    }

    /// Like AVSpeechSynthesizer, a stop reports each utterance as done a
    /// moment later (didCancel).
    func stopSpeaking() {
        stopCount += 1
        let stopped = queued
        queued.removeAll()
        Task { @MainActor in stopped.forEach { $0.done() } }
    }

    /// The utterance being said reaches its end.
    func finishCurrent() {
        guard !queued.isEmpty else { return }
        queued.removeFirst().done()
    }
}

/// Waits (briefly) for something that happens on a later main-actor turn.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
struct SpeechAudioTests {
    @Test func audioGoesOffOnlyWhenTheLastClaimIsReleased() async {
        let session = AudioSessionSpy()
        let audio = SpeechAudio(session: session)

        #expect(await audio.acquire())
        #expect(await audio.acquire())
        audio.release()
        #expect(session.offCount == 0)
        #expect(audio.claims == 1)

        audio.release()
        #expect(session.events == ["on", "on", "off"])
        // A stray extra release can't drive the count negative or switch
        // audio off twice.
        audio.release()
        #expect(audio.claims == 0)
        #expect(session.offCount == 1)
    }

    @Test func aClaimThatCantStartAudioLeavesOthersTalking() async {
        let session = AudioSessionSpy()
        let audio = SpeechAudio(session: session)
        #expect(await audio.acquire())

        session.activates = false
        #expect(await !audio.acquire())
        #expect(audio.claims == 1)
        #expect(session.offCount == 0)
    }

    @Test func aFailedClaimOnItsOwnLeavesAudioOff() async {
        let session = AudioSessionSpy()
        session.activates = false
        let audio = SpeechAudio(session: session)
        #expect(await !audio.acquire())
        #expect(audio.claims == 0)
        #expect(session.events.last == "off")
    }
}

@MainActor
struct AnnouncerTests {
    private func announcer(
        _ synthesizer: SynthesizerSpy,
        _ session: AudioSessionSpy,
        timeout: Duration = .seconds(30),
        posted: @escaping (UNNotificationRequest) -> Void = { _ in }
    ) -> Announcer {
        Announcer(
            synthesizer: synthesizer,
            audio: SpeechAudio(session: session),
            speechTimeout: timeout,
            postRequest: { posted($0) }
        )
    }

    /// Two presses in a row: the first answer stops and its caller returns
    /// straight away; audio stays on until the second answer is done.
    @Test func aSecondAnswerCutsTheFirstShortAndBothReturn() async {
        let synthesizer = SynthesizerSpy()
        let session = AudioSessionSpy()
        let announcer = announcer(synthesizer, session)

        let first = Task { await announcer.speakAnswer("first", title: "t", notificationID: "action-button") }
        #expect(await eventually { synthesizer.current == "first" })
        let second = Task { await announcer.speakAnswer("second", title: "t", notificationID: "action-button") }
        #expect(await eventually { synthesizer.current == "second" })

        await first.value
        #expect(synthesizer.stopCount == 1)
        #expect(synthesizer.said == ["first", "second"])
        // The first answer's cancellation doesn't end the second, and audio
        // is still on for it.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(synthesizer.current == "second")
        #expect(session.offCount == 0)

        synthesizer.finishCurrent()
        await second.value
        #expect(session.offCount == 1)
        #expect(session.events.last == "off")
    }

    @Test func anAnswerThatNeverReportsFinishingStillReturns() async {
        let synthesizer = SynthesizerSpy()
        let session = AudioSessionSpy()
        let announcer = announcer(synthesizer, session, timeout: .milliseconds(50))

        await announcer.speakAnswer("hello", title: "t", notificationID: "action-button")
        #expect(synthesizer.said == ["hello"])
        #expect(session.events == ["on", "off"])
    }

    @Test func theActionButtonsFallbackNotificationDoesntReplaceARideAlert() async {
        let synthesizer = SynthesizerSpy()
        let session = AudioSessionSpy()
        session.activates = false
        var posted: [String] = []
        let announcer = announcer(synthesizer, session) { posted.append($0.identifier) }

        await announcer.speakAnswer("Nearest dock answer", title: "Nearest dock", notificationID: NearestDockAnnouncement.notificationID)
        await announcer.announce("Arrival answer", title: "Docking near school")

        #expect(posted == ["action-button", "ride-arrival"])
        #expect(synthesizer.said.isEmpty)
    }

    @Test func aSpokenArrivalPostsAQuietNotification() async {
        let synthesizer = SynthesizerSpy()
        var levels: [UNNotificationInterruptionLevel] = []
        let announcer = announcer(synthesizer, AudioSessionSpy()) { levels.append($0.content.interruptionLevel) }
        let arrival = Task { await announcer.announce("Arrival answer", title: "Docking near school") }
        #expect(await eventually { synthesizer.isSpeaking })
        // Nothing posted while it's being said, so Siri doesn't read it over the voice.
        #expect(levels.isEmpty)
        synthesizer.finishCurrent()
        await arrival.value
        #expect(synthesizer.said == ["Arrival answer"])
        #expect(levels == [.passive])
    }

    /// The bug this guards against: each voice used to turn audio off when
    /// it went quiet, cutting off whatever the other was still saying.
    @Test func anAnswerEndingDoesntCutOffDirections() async {
        let session = AudioSessionSpy()
        let audio = SpeechAudio(session: session)
        let guidanceVoice = SynthesizerSpy()
        let answerVoice = SynthesizerSpy()
        let prompter = VoicePrompter(synthesizer: guidanceVoice, audio: audio)
        let announcer = Announcer(synthesizer: answerVoice, audio: audio, postRequest: { _ in })

        prompter.say("Turn left on Bergen Street.")
        #expect(await eventually { guidanceVoice.isSpeaking })
        let answer = Task { await announcer.announce("Arriving.", title: "t") }
        #expect(await eventually { answerVoice.isSpeaking })

        answerVoice.finishCurrent()
        await answer.value
        #expect(session.offCount == 0)

        guidanceVoice.finishCurrent()
        #expect(await eventually { session.offCount == 1 })
        #expect(audio.claims == 0)
    }
}

@MainActor
struct VoicePrompterTests {
    @Test func holdsAudioUntilTheLastPromptIsSaid() async {
        let session = AudioSessionSpy()
        let audio = SpeechAudio(session: session)
        let voice = SynthesizerSpy()
        let prompter = VoicePrompter(synthesizer: voice, audio: audio)

        prompter.say("In 500 feet, turn right.")
        prompter.say("Turn right on Smith Street.")
        #expect(await eventually { voice.said.count == 2 })
        #expect(audio.claims == 1)

        voice.finishCurrent()
        #expect(session.offCount == 0)
        voice.finishCurrent()
        #expect(session.offCount == 1)
        #expect(audio.claims == 0)
    }

    @Test func dropsAPromptWhenAudioCantStart() async {
        let session = AudioSessionSpy()
        session.activates = false
        let audio = SpeechAudio(session: session)
        let voice = SynthesizerSpy()
        let prompter = VoicePrompter(synthesizer: voice, audio: audio)

        prompter.say("Turn left.")
        await prompter.waitUntilDone(timeout: .milliseconds(10))
        #expect(voice.said.isEmpty)
        #expect(audio.claims == 0)
    }

    @Test func guidanceSaysAnAnswerInTheDirectionsVoice() async {
        let session = AudioSessionSpy()
        let voice = SynthesizerSpy()
        let guidance = GuidanceSession(prompter: VoicePrompter(synthesizer: voice, audio: SpeechAudio(session: session)))

        let said = Task { await guidance.say("The nearest dock is Smith and Bergen.") }
        #expect(await eventually { voice.current == "The nearest dock is Smith and Bergen." })
        voice.finishCurrent()
        await said.value
        #expect(session.events == ["on", "off"])
    }
}
