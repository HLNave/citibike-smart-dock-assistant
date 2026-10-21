//
//  SpeakNearestDockIntent.swift
//  Dock Finder
//
//  The Action Button's action: one press, and Dock Finder says the
//  nearest dock with room out loud, through the rider's headphones. It
//  never asks anything (see NearestDockAnnouncement for why).
//
//  Compiled into the widget extension too, so the extension's Action
//  Button control (SpeakNearestDockControl) can name it. It's an
//  AudioPlaybackIntent: like a podcast app's play button, iOS performs it
//  in the app's process (where location, the network and the audio
//  session are available) and runs it with the phone locked. As a
//  LiveActivityIntent, iOS asked to unlock first. The extension's copy is
//  never run.
//

import AppIntents

struct SpeakNearestDockIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Speak Nearest Dock"
    static let description = IntentDescription(
        "Says the nearest Citi Bike station with room to return your bike, out loud through your headphones, without asking anything. Made for the Action Button."
    )
    static let supportedModes: IntentModes = .background
    /// Runs from the Lock Screen and the Action Button without unlocking.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    #if WIDGET_EXTENSION
    /// Shortcuts lists the app's copy; this one only backs the control.
    static let isDiscoverable = false
    #endif

    /// Returns what was said, so a shortcut can use it too. There's no
    /// dialog: when the Action Button runs an action, iOS shows its dialog
    /// instead of speaking it, so the app speaks the answer itself.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        #if WIDGET_EXTENSION
        return .result(value: "")
        #else
        return .result(value: await NearestDockAnnouncement.live.run())
        #endif
    }
}
