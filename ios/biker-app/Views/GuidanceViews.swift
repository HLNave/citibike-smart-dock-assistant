//
//  GuidanceViews.swift
//  Dock Finder
//
//  The Direct Me button under every dock answer, and the home screen card
//  that shows the next turn while guidance runs.
//

import CoreLocation
import SwiftUI

/// Starts spoken turn-by-turn guidance to `station`.
struct DirectMeButton: View {
    let station: DockStation
    /// The full dock this answer steered away from, if any; counted as
    /// saved once the rider asks for directions.
    var avoided: AvoidedDock? = nil

    private let guidance = GuidanceSession.shared
    @State private var isStarting = false
    @State private var error: DockFinderError?

    var body: some View {
        VStack(spacing: 8) {
            if guidance.station?.id == station.id {
                Label("Directing you there", systemImage: "location.north.line.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Button {
                    Task { await start() }
                } label: {
                    // Built by hand rather than with Label, so the icon and
                    // title stay centered together in List rows too.
                    HStack(spacing: 8) {
                        if isStarting {
                            ProgressView()
                        } else {
                            Image(systemName: "location.north.line.fill")
                        }
                        Text(isStarting ? "Finding a route…" : "Direct Me")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isStarting)
            }
            if let error {
                Text(error.localizedStringResource)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        if LocationService.shared.authorizationStatus == .notDetermined {
            _ = await LocationService.shared.requestWhenInUseAuthorization()
        }
        do {
            _ = try await guidance.start(to: station, siriWillSay: nil)
            error = nil
            SavingsStore.shared.record(
                DockAnswer(text: "", station: station, avoided: avoided),
                from: LocationService.shared.lastKnownLocation,
                context: "app"
            )
        } catch let failure as DockFinderError {
            error = failure
        } catch {}
    }
}

/// The next turn while guiding; the arrival message afterwards.
struct GuidanceCard: View {
    private let guidance = GuidanceSession.shared

    var body: some View {
        if let progress = guidance.progress {
            ActiveDirectionsCard(progress: progress, docksOpen: guidance.docksOpen) {
                Task { await guidance.stop() }
            }
        } else if let arrival = guidance.lastArrival {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(arrival)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    guidance.dismissLastArrival()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}

/// Laid out like a navigation banner: the turn and its distance up top,
/// the dock and how far it is underneath, then Stop.
private struct ActiveDirectionsCard: View {
    let progress: GuidanceProgress
    let docksOpen: Int?
    let onStop: () -> Void

    var body: some View {
        let instruction = progress.nextManeuver.map { Speech.instruction($0.instruction) } ?? "Head to the dock"
        let symbol = GuidanceActivityAttributes.ContentState.maneuverSymbol(for: instruction)

        VStack(alignment: .leading, spacing: 16) {
            Label("Directions", systemImage: "location.north.line.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)

            if let current = progress.currentInstruction {
                Text(current)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let distance = progress.distanceToNextManeuver {
                        Text(Speech.length(distance))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                    Text(instruction)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.route.station.spokenName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(Speech.length(progress.remaining)) to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let docksOpen {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(docksOpen)")
                            .font(.title3.bold())
                            .monospacedDigit()
                        Text(docksOpen == 1 ? "dock open" : "docks open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if LocationService.shared.authorizationStatus != .authorizedAlways {
                Text("Keep Dock Finder open, or allow location access all the time, to hear each turn with your phone locked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: .destructive, action: onStop) {
                Text("Stop Directions")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}
