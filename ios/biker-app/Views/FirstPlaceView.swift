//
//  FirstPlaceView.swift
//  Dock Finder
//
//  The onboarding step that has the rider save one place (school, work,
//  home) before they reach the Siri screen, since rides, arrival alerts
//  and "check my school dock" all start from a saved place. Continue
//  stays off until there's one; places restored from the keychain count.
//

import SwiftUI

struct FirstPlaceView: View {
    let onContinue: () -> Void

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @State private var showsAddPlace = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Add your first place")
                        .font(.title.bold())
                    Text("Save somewhere you ride to often, like school, work or home. Its name is what you'll say to Siri.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Search for the address, or use where you are now.", systemImage: "magnifyingglass")
                    Label("Give it a short name, like “school”.", systemImage: "character.cursor.ibeam")
                    Label("Choose how far out you want to hear where to dock.", systemImage: "circle.dashed")
                }
                .font(.subheadline)

                if let place = savedPlaces.places.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(place.name) is saved", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Now you can say “Hey Siri, ask Dock Finder to start a ride to \(place.name.lowercased())”, and Dock Finder tells you where to dock as you get there. You can pick its usual dock later, from the home screen.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 16))
                }

                VStack(spacing: 12) {
                    if savedPlaces.places.isEmpty {
                        Button {
                            showsAddPlace = true
                        } label: {
                            Label("Add a Place", systemImage: "plus")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Add Another Place") { showsAddPlace = true }
                            .controlSize(.large)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsAddPlace) {
            AddPlaceView()
        }
    }
}

#Preview {
    FirstPlaceView(onContinue: {})
        .environment(SavedPlacesStore.shared)
}
