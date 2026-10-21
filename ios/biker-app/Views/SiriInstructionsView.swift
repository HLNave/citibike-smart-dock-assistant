//
//  SiriInstructionsView.swift
//  Dock Finder
//

import AppIntents
import CoreLocation
import SwiftUI

struct SiriInstructionsView: View {
    let onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizationStatus = LocationService.shared.authorizationStatus

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Use Dock Finder with Siri")
                        .font(.title.bold())
                    Text("Every request starts with “Ask Dock Finder”, said in one go.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Starting a ride")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "“Hey Siri, ask Dock Finder to start a ride to school.”", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                    PhraseRow(text: "Works with any saved place. Going somewhere else? Say “…to start a ride”, and when Siri asks “Where are you heading?”, say a landmark (“Union Square”) or an address.", systemImage: "mappin.and.ellipse")
                    Text("As you get close, Dock Finder tells you where to dock, through your headphones, even with your phone locked. Say “yes” when Siri asks “Want me to guide you to the dock when you're close?” to also hear each turn on the way there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Need a dock right now?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "“Hey Siri, ask Dock Finder to find a dock.”", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                    Text("Siri tells you the nearest station that has room, then asks “Want me to direct you there?” Say “yes” to hear each turn through your headphones.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Got an Action Button?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "Press and hold it to hear the nearest dock with room.", systemImage: "button.vertical.left.press.fill")
                        .font(.title3.weight(.semibold))
                    Text("Set it up once in Settings › Action Button › Controls › Choose a Control › Speak Nearest Dock. Dock Finder answers through your headphones, even with your phone locked, and never asks anything. For directions, then say “Hey Siri, ask Dock Finder to direct me.”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    Text("More")
                        .font(.headline)
                    ForEach(Self.morePhrases, id: \.self) { phrase in
                        PhraseRow(text: phrase, systemImage: "mic")
                            .font(.subheadline)
                    }
                    Text("Siri knows your usual and backup docks, the stations near your saved places, and stations you've checked recently by name. For any other station, say “…to check a station” and Siri asks which one. No “Hey Siri”? Hold the side button, or long-press an AirPods stem, and say the same thing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                SiriTipView(intent: StartRideIntent())

                if locationIsUnavailable {
                    LocationRequiredNotice()
                }

                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)

                DockLookupSection(buttonTitle: "Try Dock Finder", prominent: false)

                Button(action: onDone) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            // Pick up changes made in Settings while the app was backgrounded.
            if phase == .active {
                authorizationStatus = LocationService.shared.authorizationStatus
            }
        }
    }

    static let morePhrases = [
        "“Ask Dock Finder to check my school dock.”",
        "“Ask Dock Finder to find a dock near work.”",
        "“Ask Dock Finder if Mercer and Bleecker is full.”",
        "“Ask Dock Finder to find a dock somewhere else.”",
        "“Ask Dock Finder to direct me to school.”",
        "“Ask Dock Finder to stop guiding me.”",
        "“Ask Dock Finder to end my bike ride.”",
        "“Ask Dock Finder how many bikes are out.”",
        "“Ask Dock Finder a question.” Then say anything, in your own words.",
    ]

    private var locationIsUnavailable: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

private struct PhraseRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
    }
}

private struct LocationRequiredNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location access is off", systemImage: "location.slash.fill")
                .font(.headline)
            Text("Finding the nearest dock requires location permission. Siri will ask you to grant access until it's turned on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            OpenSettingsButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        SiriInstructionsView(onDone: {})
    }
}
