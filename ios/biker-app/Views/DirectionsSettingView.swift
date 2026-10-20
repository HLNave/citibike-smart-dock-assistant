//
//  DirectionsSettingView.swift
//  Dock Finder
//
//  The Directions setting: what Siri does after it names a dock.
//

import SwiftUI

struct DirectionsSettingView: View {
    @State private var preference = DirectionsPreference.current()

    var body: some View {
        List {
            Section {
                Picker("When Siri finds a dock", selection: $preference) {
                    ForEach(DirectionsPreference.allCases) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(option.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("When Siri finds a dock")
            } footer: {
                Text("Rides you start with Siri follow this too: Start Right Away guides you to the dock when you're close, Don't Offer never does, and Ask Me asks each time.")
            }
        }
        .navigationTitle("Directions")
        .onChange(of: preference) { _, choice in
            DirectionsPreference.set(choice)
        }
    }
}

#Preview {
    NavigationStack {
        DirectionsSettingView()
    }
}
