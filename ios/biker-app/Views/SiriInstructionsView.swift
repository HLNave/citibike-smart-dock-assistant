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
                    Text("Just say")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhraseRow(text: "“Hey Siri, ask Dock Finder.”", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                    PhraseRow(text: "Siri asks: “Where are you headed, or which station?”", systemImage: "bubble.left.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Then answer with")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(Self.answers, id: \.self) { answer in
                            Text("• \(answer)")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    Text("One-step shortcuts")
                        .font(.headline)
                    ForEach(Self.oneStepPhrases, id: \.self) { phrase in
                        PhraseRow(text: phrase, systemImage: "mic")
                            .font(.subheadline)
                    }
                    Text("Faster when Siri hears them right, but Siri sometimes mistakes “dock” for “doc”. If that happens, use “ask Dock Finder” instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                SiriTipView(intent: AskDockFinderIntent())

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

    static let answers = [
        "a saved place: “school”",
        "a place: “near Union Square”",
        "a station: “Mercer and Bleecker”",
        "“near me”",
        "“how many bikes are out?”",
    ]

    static let oneStepPhrases = [
        "“Hey Siri, find a dock with Dock Finder.”",
        "“Hey Siri, find a dock near school with Dock Finder.”",
        "“Hey Siri, check a station with Dock Finder.”",
        "“Hey Siri, Citi Bike status in Dock Finder.”",
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
