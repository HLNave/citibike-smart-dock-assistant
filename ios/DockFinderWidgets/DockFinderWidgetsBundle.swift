//
//  DockFinderWidgetsBundle.swift
//  Dock Finder Widgets
//
//  The widget extension: the ride and guidance Live Activity (the app
//  decides what it shows; see DockFinderLiveActivity), and the Ask Dock
//  Finder control for the Action Button, Control Center and Lock Screen.
//

import SwiftUI
import WidgetKit

@main
struct DockFinderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GuidanceLiveActivity()
        AskDockFinderControl()
    }
}
