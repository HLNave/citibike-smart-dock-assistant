//
//  DockFinderWidgetsBundle.swift
//  Dock Finder Widgets
//
//  The widget extension: the ride and guidance Live Activity (the app
//  decides what it shows; see DockFinderLiveActivity) and the Action
//  Button control.
//

import SwiftUI
import WidgetKit

@main
struct DockFinderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GuidanceLiveActivity()
        SpeakNearestDockControl()
    }
}
