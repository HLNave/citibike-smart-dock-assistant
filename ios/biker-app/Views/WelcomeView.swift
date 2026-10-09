//
//  WelcomeView.swift
//  Dock Finder
//

import CoreLocation
import SwiftUI

/// First-launch flow: Welcome → Siri instructions.
struct OnboardingFlowView: View {
    @Environment(OnboardingState.self) private var onboarding
    @State private var showsSiriInstructions = false

    var body: some View {
        NavigationStack {
            WelcomeView(onContinue: { showsSiriInstructions = true })
                .navigationDestination(isPresented: $showsSiriInstructions) {
                    SiriInstructionsView(onDone: onboarding.finishOnboarding)
                }
        }
    }
}

struct WelcomeView: View {
    let onContinue: () -> Void

    @Environment(OnboardingState.self) private var onboarding
    @State private var isRequesting = false
    @State private var showsLocationDeniedAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bicycle.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Dock Finder")
                    .font(.largeTitle.bold())
                Text("Find available Citi Bike docks with Siri.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button(action: enableTapped) {
                    Text("Enable Dock Finder with Siri")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Text("Set up location access and learn how to use Dock Finder hands-free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: 500)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Location Access Is Off", isPresented: $showsLocationDeniedAlert) {
            OpenSettingsAlertButton()
            Button("Continue", action: onContinue)
        } message: {
            Text("Dock Finder needs your location to find nearby docks. You can turn it on in Settings › Privacy & Security › Location Services › Dock Finder.")
        }
    }

    private func enableTapped() {
        onboarding.markIntroCompleted()
        isRequesting = true
        Task {
            let status = await LocationService.shared.requestWhenInUseAuthorization()
            isRequesting = false
            switch status {
            case .denied, .restricted:
                showsLocationDeniedAlert = true
            default:
                onContinue()
            }
        }
    }
}

private struct OpenSettingsAlertButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}

#Preview {
    OnboardingFlowView()
        .environment(OnboardingState(defaults: UserDefaults(suiteName: "preview")!))
}
