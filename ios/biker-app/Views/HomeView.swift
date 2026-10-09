//
//  HomeView.swift
//  Dock Finder
//

import SwiftUI

struct HomeView: View {
    @State private var showsSiriInstructions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "bicycle.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Dock Finder")
                        .font(.largeTitle.bold())
                    Text("Find the nearest Citi Bike station with an open dock.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                DockLookupSection(buttonTitle: "Find Nearest Dock", prominent: true)

                Button {
                    showsSiriInstructions = true
                } label: {
                    Label("How to Use with Siri", systemImage: "mic")
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsSiriInstructions) {
            NavigationStack {
                SiriInstructionsView(onDone: { showsSiriInstructions = false })
            }
        }
    }
}

#Preview {
    HomeView()
}
