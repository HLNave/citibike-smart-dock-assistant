//
//  FindDockIntent.swift
//  Dock Finder
//

import AppIntents

struct FindDockIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Dock"
    static let description = IntentDescription(
        "Finds the nearest Citi Bike station with an available return dock."
    )

    /// Run without bringing the app to the foreground. Everything this
    /// intent needs (location + network) is available in the background
    /// while the intent is running.
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Errors conform to CustomLocalizedStringResourceConvertible, so Siri
        // speaks their message when they propagate.
        let result = try await DockFinderService.live.findNearestDock()
        return .result(dialog: "\(result.summary)")
    }
}
