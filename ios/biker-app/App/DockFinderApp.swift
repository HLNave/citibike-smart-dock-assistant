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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        // Also runs when iOS relaunches the app in the background for a
        // ride's geofence, so tracking resumes and the arrival is handled.
        Task { await RideTracker.shared.resume() }
        // Tell Siri the saved place names for "Check my school dock". iOS can
        // forget them after an update or reinstall, and places restored from
        // the keychain don't count as a change.
        SavedPlacesStore.refreshSiriPhrases()
        // Same for arriving at a saved place without a ride.
        Task { await PlaceArrivalMonitor.shared.sync() }
        // Usage events that couldn't be sent last time. (Opening the app
        // is logged when it comes to the foreground, below.)
        Task { await Metrics.shared.flush() }
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            // For the team's Users tab: last opened, and how often riders come back.
            if phase == .active {
                Metrics.shared.logOpened()
            }
        }
    }
}
