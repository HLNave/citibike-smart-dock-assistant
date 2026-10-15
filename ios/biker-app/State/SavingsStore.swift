//
//  SavingsStore.swift
//  Dock Finder
//
//  Every full dock Dock Finder steered the rider away from, kept on this
//  iPhone for the savings dashboard. Each one is also sent to the team's
//  sheet if the rider agreed to share usage data.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class SavingsStore {
    static let shared = SavingsStore(metrics: .shared)

    nonisolated static let storageKey = "savingsEvents"

    private let defaults: UserDefaults
    private let metrics: Metrics?

    private(set) var events: [SavingsEvent]

    init(defaults: UserDefaults = .standard, metrics: Metrics? = nil) {
        self.defaults = defaults
        self.metrics = metrics
        events = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([SavingsEvent].self, from: $0) } ?? []
    }

    var thisMonth: SavingsSummary {
        SavingsSummary.of(events, since: SavingsSummary.startOfMonth(containing: .now))
    }

    var allTime: SavingsSummary {
        SavingsSummary.of(events)
    }

    /// Counts `answer` if it steered the rider away from a full dock. The
    /// same redirect again within half an hour counts once.
    ///
    /// - Parameters:
    ///   - origin: where the rider was, for the detour estimate.
    ///   - context: where it happened, e.g. "siri" or "ride_arrival".
    @discardableResult
    func record(_ answer: DockAnswer, from origin: CLLocation?, context: String, now: Date = .now) -> SavingsEvent? {
        guard let avoided = answer.avoided, let chosen = answer.station else { return nil }
        let isRepeat = events.contains {
            $0.avoided.id == avoided.id && $0.chosenID == chosen.id
                && now.timeIntervalSince($0.date) < SavingsModel.duplicateWindow
        }
        guard !isRepeat else { return nil }

        let event = SavingsEvent(
            id: UUID(),
            date: now,
            avoided: avoided,
            chosenID: chosen.id,
            chosenName: chosen.name,
            minutes: SavingsModel.minutesSaved(from: origin, avoided: avoided.location, chosen: chosen.location),
            context: context
        )
        events.append(event)
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.storageKey)
        }
        metrics?.log(
            "full_dock_avoided",
            station: chosen.name,
            avoidedStation: avoided.name,
            minutesSaved: event.minutes,
            location: origin,
            details: ["context": context, "problem": avoided.problem]
        )
        return event
    }
}
