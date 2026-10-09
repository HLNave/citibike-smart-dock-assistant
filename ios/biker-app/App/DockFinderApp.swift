//
//  DockFinderApp.swift
//  Dock Finder
//

import SwiftUI

@main
struct DockFinderApp: App {
    @State private var onboarding = OnboardingState()
    @State private var savedPlaces = SavedPlacesStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarding.isShowingOnboarding {
                    OnboardingFlowView()
                } else {
                    HomeView()
                }
            }
            .environment(onboarding)
            .environment(savedPlaces)
        }
    }
}
