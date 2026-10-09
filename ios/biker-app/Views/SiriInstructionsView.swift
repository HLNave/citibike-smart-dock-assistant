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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Just say")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(Self.phrases, id: \.self) { phrase in
                        Label {
                            Text(phrase)
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    Text("Saved-place phrases work for any place you add, like “near work” or “near home”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))

                SiriTipView(intent: FindDockIntent())

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

    static let phrases = [
        "“Hey Siri, find a dock with Dock Finder.”",
        "“Hey Siri, find a dock near school with Dock Finder.”",
        "“Hey Siri, find a dock near a place with Dock Finder.”",
        "“Hey Siri, check a station with Dock Finder.”",
        "“Hey Siri, Citi Bike status in Dock Finder.”",
        "“Hey Siri, ask Dock Finder.”",
    ]

    private var locationIsUnavailable: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
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
