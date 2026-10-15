//
//  SavingsStore.swift
//  Dock Finder
//
//  Every full dock Dock Finder steered the rider away from, and every
//  dock answer it gave by voice (a time the rider didn't take out their
//  phone), kept on this iPhone for the savings dashboard. Each is also
//  sent to the team's sheet if the rider agreed to share usage data.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class SavingsStore {
    static let shared = SavingsStore(metrics: .shared)

    nonisolated static let storageKey = "savingsEvents"
    nonisolated static let handsFreeKey = "handsFreeChecks"

    private let defaults: UserDefaults
    private let metrics: Metrics?

    private(set) var events: [SavingsEvent]
    private(set) var handsFree: [HandsFreeCheck]

    init(defaults: UserDefaults = .standard, metrics: Metrics? = nil) {
        self.defaults = defaults
        self.metrics = metrics
        events = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([SavingsEvent].self, from: $0) } ?? []
        handsFree = defaults.data(forKey: Self.handsFreeKey)
            .flatMap { try? JSONDecoder().decode([HandsFreeCheck].self, from: $0) } ?? []
    }

    var hasMeasuredSavings: Bool { !events.isEmpty || !handsFree.isEmpty }

    var thisMonth: SavingsSummary {
        SavingsSummary.of(events, handsFree: handsFree, since: SavingsSummary.startOfMonth(containing: .now))
    }

    var allTime: SavingsSummary {
        SavingsSummary.of(events, handsFree: handsFree)
    }

    /// Counts a dock answer given by voice. Checks within a few minutes of
    /// each other (a Siri answer, then "yes, direct me") count once.
    @discardableResult
    func recordHandsFree(context: String, now: Date = .now) -> HandsFreeCheck? {
        if let last = handsFree.last, now.timeIntervalSince(last.date) < SavingsModel.handsFreeWindow {
            return nil
        }
        let check = HandsFreeCheck(id: UUID(), date: now, context: context)
        handsFree.append(check)
        if let data = try? JSONEncoder().encode(handsFree) {
            defaults.set(data, forKey: Self.handsFreeKey)
        }
        metrics?.log("hands_free_check", minutesSaved: SavingsModel.handsFreeMinutes, details: ["context": context])
        return check
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
