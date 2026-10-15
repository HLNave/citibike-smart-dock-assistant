//
//  DockFinderWidgetsBundle.swift
//  Dock Finder Widgets
//
//  The widget extension. It only draws the ride and guidance Live
//  Activity; the app decides what it shows (see DockFinderLiveActivity).
//

import SwiftUI
import WidgetKit

@main
struct DockFinderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GuidanceLiveActivity()
    }
}
