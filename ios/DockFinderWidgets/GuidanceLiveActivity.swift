//
//  GuidanceLiveActivity.swift
//  Dock Finder Widgets
//
//  The Lock Screen banner and Dynamic Island for a ride and for
//  turn-by-turn guidance to a dock: the next turn, how far, and the dock
//  with its open docks. Big and simple, for a glance at a red light.
//

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.16, green: 0.88, blue: 0.92)
private let background = Color(red: 0.03, green: 0.17, blue: 0.38)

struct GuidanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidanceActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DockCount(state: context.state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if let current = context.state.current, context.state.phase == .guiding {
                            Text(current)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(context.state.headline)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let dock = context.state.dockName, context.state.phase == .guiding {
                        Label("To \(dock)", systemImage: "bicycle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(compactDetail(context.state))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }

    /// "500 ft" from "In 500 feet"; the dock count once arrived.
    private func compactDetail(_ state: GuidanceActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .guiding:
            return state.detail
                .replacingOccurrences(of: "In ", with: "")
                .replacingOccurrences(of: " feet", with: " ft")
                .replacingOccurrences(of: " miles", with: " mi")
                .replacingOccurrences(of: " mile", with: " mi")
                .replacingOccurrences(of: " meters", with: " m")
                .replacingOccurrences(of: " kilometers", with: " km")
        case .riding:
            return "Riding"
        case .arrived:
            return state.docksOpen.map { "\($0) docks" } ?? "Dock"
        }
    }
}

private struct LockScreenView: View {
    let state: GuidanceActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 3) {
                // Now, then the next turn: "Head north on 6th Avenue" above
                // "Turn right onto 12th Street · In 0.2 miles".
                if let current = state.current, state.phase == .guiding {
                    Text(current)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Text(state.headline)
                    .font(.headline)
                    .lineLimit(2)
                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                if let dock = state.dockName, state.phase == .guiding {
                    Text("To \(dock)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 8)
            DockCount(state: state)
        }
        .padding()
    }
}

/// "8 docks", big enough to read at a glance.
private struct DockCount: View {
    let state: GuidanceActivityAttributes.ContentState

    var body: some View {
        if let docks = state.docksOpen {
            VStack(spacing: 0) {
                Text("\(docks)")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(docks == 1 ? "dock" : "docks")
                    .font(.caption2)
            }
            .foregroundStyle(accent)
        }
    }
}
