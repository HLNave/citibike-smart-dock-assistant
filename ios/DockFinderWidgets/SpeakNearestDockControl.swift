//
//  SpeakNearestDockControl.swift
//  Dock Finder Widgets
//
//  The Action Button control: Settings › Action Button › Controls lists
//  it as "Speak Nearest Dock", so the rider can pick it without building
//  a shortcut first. iOS also offers every control in Control Center and on
//  the Lock Screen; there's no way to limit one to the Action Button.
//
//  Pressing it runs SpeakNearestDockIntent in the app's process (it's a
//  LiveActivityIntent), which says the nearest dock with room out loud.
//

import AppIntents
import SwiftUI
import WidgetKit

struct SpeakNearestDockControl: ControlWidget {
    static let kind = "SpeakNearestDock"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: SpeakNearestDockIntent()) {
                Label("Nearest Dock", systemImage: "bicycle")
                    // The Action Button shows this as its hint (exact
                    // wording not yet seen on a phone).
                    .controlWidgetActionHint("Hear Nearest Dock")
            }
        }
        .displayName("Speak Nearest Dock")
        .description("Says the nearest Citi Bike dock with room, out loud through your headphones.")
    }
}
