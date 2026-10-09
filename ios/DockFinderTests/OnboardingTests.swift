//
//  OnboardingTests.swift
//  DockFinderTests
//

import Foundation
import Testing
@testable import DockFinder

@MainActor
struct OnboardingTests {
    let suiteName = "DockFinderTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func firstLaunchShowsOnboarding() {
        let state = OnboardingState(defaults: defaults)
        #expect(!state.hasCompletedIntro)
        #expect(state.isShowingOnboarding)
    }

    @Test func markingIntroCompletePersistsWithoutLeavingTheFlow() {
        let state = OnboardingState(defaults: defaults)
        state.markIntroCompleted()
        #expect(state.hasCompletedIntro)
        // The user still needs to see the Siri instructions this session.
        #expect(state.isShowingOnboarding)
        #expect(defaults.bool(forKey: OnboardingState.introCompletedKey))
    }

    @Test func finishingOnboardingLeavesTheFlow() {
        let state = OnboardingState(defaults: defaults)
        state.finishOnboarding()
        #expect(!state.isShowingOnboarding)
        #expect(state.hasCompletedIntro)
    }

    @Test func returningUsersSkipOnboarding() {
        OnboardingState(defaults: defaults).markIntroCompleted()
        let relaunched = OnboardingState(defaults: defaults)
        #expect(relaunched.hasCompletedIntro)
        #expect(!relaunched.isShowingOnboarding)
    }
}
