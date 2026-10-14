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

    private let guidance = GuidanceSession.shared
    @State private var isStarting = false
    @State private var error: DockFinderError?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if guidance.station?.id == station.id {
                Label("Directing you there", systemImage: "location.north.line.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            } else {
                Button {
                    Task { await start() }
                } label: {
                    Label(isStarting ? "Finding a route…" : "Direct Me", systemImage: "location.north.line.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStarting)
            }
            if let error {
                Text(error.localizedStringResource)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        if LocationService.shared.authorizationStatus == .notDetermined {
            _ = await LocationService.shared.requestWhenInUseAuthorization()
        }
        do {
            _ = try await guidance.start(to: station, speak: true)
            error = nil
        } catch let failure as DockFinderError {
            error = failure
        } catch {}
    }
}

/// The next turn, the dock and a Stop button while guiding; the arrival
/// message afterwards.
struct GuidanceCard: View {
    private let guidance = GuidanceSession.shared

    var body: some View {
        if let progress = guidance.progress {
            let state = GuidanceActivityAttributes.ContentState.guiding(progress, docksOpen: guidance.docksOpen)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.headline)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Label {
                    Text(dockLine(progress.route.station))
                } icon: {
                    Image(systemName: "bicycle")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if LocationService.shared.authorizationStatus != .authorizedAlways {
                    Text("Keep Dock Finder open, or allow location access all the time, to hear each turn with your phone locked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    Task { await guidance.stop() }
                } label: {
                    Label("Stop Directions", systemImage: "xmark.circle")
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 16))
        } else if let arrival = guidance.lastArrival {
            HStack(alignment: .top) {
                Label(arrival, systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    guidance.dismissLastArrival()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }

    private func dockLine(_ station: DockStation) -> String {
        var line = "To \(station.spokenName)"
        if let docks = guidance.docksOpen { line += ", \(Speech.docksOpen(docks))" }
        if let progress = guidance.progress { line += " · \(Speech.length(progress.remaining)) to go" }
        return line
    }
}
