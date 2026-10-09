//
//  OnboardingState.swift
//  Dock Finder
//
//  Local walkthrough progress only. This has no effect on whether Siri or
//  Shortcuts can run Find Dock — that is always available once installed.
//

import Foundation
import Observation

@Observable
final class OnboardingState {
    static let introCompletedKey = "hasCompletedIntro"

    private let defaults: UserDefaults

    /// Persisted: the user has been through the welcome screen.
    private(set) var hasCompletedIntro: Bool
    /// In-session: whether the onboarding flow is on screen. Decided at
    /// launch so marking the intro complete mid-flow doesn't yank the user
    /// past the Siri instructions.
    private(set) var isShowingOnboarding: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let completed = defaults.bool(forKey: Self.introCompletedKey)
        hasCompletedIntro = completed
        isShowingOnboarding = !completed
    }

    func markIntroCompleted() {
        defaults.set(true, forKey: Self.introCompletedKey)
        hasCompletedIntro = true
    }

    func finishOnboarding() {
        markIntroCompleted()
        isShowingOnboarding = false
    }
}
