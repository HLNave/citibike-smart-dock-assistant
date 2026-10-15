//
//  AskByVoiceIntent.swift
//  Dock Finder
//
//  "Ask Dock Finder" without Siri: the action behind the Ask Dock Finder
//  control (Action Button, Control Center, Lock Screen). Dock Finder
//  listens for the question itself, so Siri's phrase matching never gets
//  in the way, and it works with the phone locked.
//
//  It's an AudioRecordingIntent: the kind of action iOS lets start the
//  microphone from the Lock Screen, as long as a Live Activity shows it's
//  listening. The type is compiled into the widget extension too, because
//  the control needs it there, but it always runs in the app, which does
//  the listening (VoiceAsk).
//

import AppIntents

struct AskByVoiceIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Ask Dock Finder by Voice"
    static let description = IntentDescription(
        "Listens for your question and answers out loud, even with your phone locked. Made for the Action Button."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VoiceAsk.shared.begin()
        #endif
        return .result()
    }
}
