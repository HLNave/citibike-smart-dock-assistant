//
//  DockFinderApp.swift
//  Dock Finder
//

import SwiftUI
import UserNotifications

@main
struct DockFinderApp: App {
    @State private var onboarding = OnboardingState()
    @State private var savedPlaces = SavedPlacesStore.shared
    @State private var rides = RideTracker.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        // Also runs when iOS relaunches the app in the background for a
        // ride's geofence, so tracking resumes and the arrival is handled.
        Task { await RideTracker.shared.resume() }
    }

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
            .environment(rides)
        }
    }
}
