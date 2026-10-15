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
                    Text("Dock Finder is available through Siri and Apple Shortcuts.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Starting a ride")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "“Hey Siri, start a ride with Dock Finder.”", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                    PhraseRow(text: "Siri asks: “Where are you heading?”", systemImage: "bubble.left.fill")
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "Say a saved place (“school”), a landmark (“Union Square”), or an address.", systemImage: "mappin.and.ellipse")
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
                    PhraseRow(text: "“Hey Siri, find a dock with Dock Finder.”", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                    Text("Siri tells you the nearest station that has room, then asks “Want me to direct you there?” Say “yes” to hear each turn through your headphones.")
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
                    Text("“Ask Dock Finder” takes anything in your own words, like “is Mercer and Bleecker full?” or “my school dock is Court and State”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                AskButtonSetupCard()

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
        "“Hey Siri, stop directions with Dock Finder.”",
        "“Hey Siri, direct me with Dock Finder.”",
        "“Hey Siri, end my ride with Dock Finder.”",
        "“Hey Siri, check my school dock with Dock Finder.”",
        "“Hey Siri, check a station with Dock Finder.”",
        "“Hey Siri, Citi Bike status in Dock Finder.”",
        "“Hey Siri, ask Dock Finder.”",
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

/// Setting up the Ask Dock Finder control: the steps iOS only lets the
/// rider do, and the microphone and speech permissions it needs (which
/// can only be asked for while the app is open).
private struct AskButtonSetupCard: View {
    @Environment(\.openURL) private var openURL
    @State private var hasPermissions = VoiceAsk.hasPermissions
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask with one press")
                .font(.headline)
            Text("Put **Ask Dock Finder** on the Action Button, Lock Screen or Control Center. Press it and Dock Finder asks “What do you need?” and answers out loud, even with your phone locked, no “Hey Siri” needed.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                PhraseRow(text: "Action Button: Settings › Action Button › Controls › Ask Dock Finder", systemImage: "button.vertical.right.press")
                PhraseRow(text: "Lock Screen: touch and hold the Lock Screen › Customize › tap a bottom button › Ask Dock Finder", systemImage: "lock")
                PhraseRow(text: "Control Center: swipe down from the top right › + › Add a Control › Ask Dock Finder", systemImage: "switch.2")
            }
            .font(.footnote)

            if hasPermissions {
                Label("Microphone and speech recognition are on", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await allow() }
                } label: {
                    Text("Allow Microphone & Speech")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
                Text("Needed once, so the button can listen. Your voice is turned into text on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func allow() async {
        isRequesting = true
        defer { isRequesting = false }
        hasPermissions = await VoiceAsk.requestPermissions()
        // Denied earlier: iOS won't ask again, so open Settings instead.
        if !hasPermissions, let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
