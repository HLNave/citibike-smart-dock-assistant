//
//  PrivacyViews.swift
//  Dock Finder
//
//  Asking whether to share usage data with the Dock Finder team (once, at
//  onboarding or on first launch after updating), and the Privacy screen
//  where riders can change their answer.
//

import SwiftUI

/// What's shared, in plain words. Used by the prompt and the Privacy screen.
struct UsageSharingExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While Dock Finder is being tested, it can send the Dock Finder team a record of how you use it, so we can measure what it saves riders and fix what doesn't work:")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("When you open and use it: rides, arrival alerts, directions and Siri answers", systemImage: "list.bullet")
                Label("Where you were at the time (your location) and the docks involved", systemImage: "location")
                Label("The time and money we estimate it saved you", systemImage: "clock.arrow.circlepath")
            }
            .font(.subheadline)
            Text("It's tied to a random ID made on this iPhone, not your email or Apple ID, and to your name only if you add one. It's stored in the team's Google Sheet, never sold, and never used for ads. You can stop sharing any time under Privacy on the home screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Lets testers be told apart in the team's sheet. Optional.
struct UsageNameField: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Your name (optional)", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
            Text("Shown next to your usage in the team's sheet, so we know who's testing. Leave it blank to stay anonymous.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// On the home screen for riders who agreed to share before names existed
/// (so never saw the name field), until they add one or tap Not Now.
struct UsageNameCard: View {
    static let dismissedKey = "usageNameCardDismissed"

    /// Sharing, no name yet, and not dismissed.
    static var shouldShow: Bool {
        UsageSharing.current() == .granted
            && UsageSharing.name() == nil
            && !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    let onDone: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add your name", systemImage: "person.crop.circle.badge.plus")
                .font(.headline)
            UsageNameField(name: $name)
                .onSubmit(save)
            HStack(spacing: 12) {
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Not Now") {
                    UserDefaults.standard.set(true, forKey: Self.dismissedKey)
                    onDone()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func save() {
        UsageSharing.setName(name)
        guard UsageSharing.name() != nil else { return }
        Metrics.shared.log("name_changed")
        onDone()
    }
}

/// The one-time question. `onDone` runs after either answer.
struct UsageSharingPrompt: View {
    let onDone: () -> Void
    @State private var name = UsageSharing.name() ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Help improve Dock Finder")
                        .font(.title.bold())
                }
                UsageSharingExplanation()
                UsageNameField(name: $name)
                    .padding(12)
                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                VStack(spacing: 12) {
                    Button {
                        choose(.granted)
                    } label: {
                        Text("Share Usage Data")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        choose(.declined)
                    } label: {
                        Text("Don't Share")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Text("Your savings dashboard works either way; it's kept on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled()
    }

    private func choose(_ choice: UsageSharing) {
        UsageSharing.set(choice)
        // Only kept if they share; a name alone is never sent.
        UsageSharing.setName(choice == .granted ? name : "")
        // They've seen the name field, so the home screen doesn't ask again.
        UserDefaults.standard.set(true, forKey: UsageNameCard.dismissedKey)
        if choice == .granted {
            Metrics.shared.log("sharing_turned_on")
        }
        onDone()
    }
}

/// Lets the rider see what's shared and turn it on or off.
struct PrivacyView: View {
    @State private var isSharing = UsageSharing.current() == .granted
    @State private var name = UsageSharing.name() ?? ""
    @State private var savedName = UsageSharing.name() ?? ""

    var body: some View {
        List {
            Section {
                Toggle("Share Usage Data", isOn: $isSharing)
            } footer: {
                Text(isSharing
                     ? "Thanks. Events are sent to the Dock Finder team as you use the app."
                     : "Nothing is sent. Turning this off also deletes anything not yet sent.")
            }
            if isSharing {
                Section("Your Name") {
                    UsageNameField(name: $name)
                        .onSubmit(saveName)
                        // Kept as typed, so the home screen knows straight away.
                        .onChange(of: name) { _, typed in UsageSharing.setName(typed) }
                }
            }
            Section("What's Shared") {
                UsageSharingExplanation()
                    .padding(.vertical, 4)
            }
            Section("Kept on This iPhone") {
                Text("Your saved places (also backed up in this iPhone's keychain so they survive reinstalling) and your savings history. Neither is shared unless usage sharing is on.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Privacy")
        .onDisappear(perform: saveName)
        .onChange(of: isSharing) { _, sharing in
            UsageSharing.set(sharing ? .granted : .declined)
            if sharing {
                Metrics.shared.log("sharing_turned_on")
            } else {
                Metrics.shared.discardQueued()
            }
        }
    }

    /// Logged when they press Done or leave the screen, so the sheet shows
    /// the new name even before they next use the app.
    private func saveName() {
        UsageSharing.setName(name)
        let current = UsageSharing.name() ?? ""
        guard current != savedName else { return }
        savedName = current
        Metrics.shared.log("name_changed")
    }
}
