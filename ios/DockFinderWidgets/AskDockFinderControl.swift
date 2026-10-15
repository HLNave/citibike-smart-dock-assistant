//
//  AskDockFinderControl.swift
//  Dock Finder Widgets
//
//  The Ask Dock Finder control: a button riders can put on the Action
//  Button, in Control Center or on the Lock Screen. Pressing it runs
//  AskByVoiceIntent in the app, which asks "What do you need?" and
//  answers out loud.
//

import AppIntents
import SwiftUI
import WidgetKit

struct AskDockFinderControl: ControlWidget {
    static let kind = "AskDockFinderControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AskByVoiceIntent()) {
                Label("Ask Dock Finder", systemImage: "bicycle")
            }
        }
        .displayName("Ask Dock Finder")
        .description("Ask about docks by voice, even with your phone locked.")
    }
}
