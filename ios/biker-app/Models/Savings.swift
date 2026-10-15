//
//  Savings.swift
//  Dock Finder
//
//  How much time and money Dock Finder saves a rider, estimated from the
//  full docks it steers them away from. Without Dock Finder, the rider
//  rides to the full dock, finds it full and rides on to one with room;
//  with it, they ride straight there. The difference, plus a moment for
//  finding the dock full, is the time saved.
//
//  On top of that, every dock answer given by voice (Siri, ride and
//  saved-place arrival alerts) is a time the rider didn't stop to take out
//  their phone: a "hands-free check", worth a minute each and counted as
//  a safety stat. Everyone is assumed to ride e-bikes, which members pay
//  for by the minute.
//

import CoreLocation
import Foundation

/// A dock Dock Finder steered the rider away from, and why.
nonisolated struct AvoidedDock: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Completes "<dock> …": "is full", "is almost full", "is closed".
    let problem: String

    init(id: String, name: String, latitude: Double, longitude: Double, problem: StationProblem) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.problem = problem.phrase
    }

    init(_ station: StationSnapshot, problem: StationProblem) {
        self.init(id: station.id, name: station.name, latitude: station.latitude, longitude: station.longitude, problem: problem)
    }

    init(_ station: DockStation, problem: StationProblem) {
        self.init(id: station.id, name: station.name, latitude: station.latitude, longitude: station.longitude, problem: problem)
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var spokenName: String { Speech.stationName(name) }
}

nonisolated enum SavingsModel {
    /// Citi Bike's member e-bike rate, in dollars per minute. Update it when
    /// Citi Bike's pricing changes.
    static let ebikeDollarsPerMinute = 0.27
    /// Typical riding speed in the city, about 15 km/h.
    static let ridingSpeed: CLLocationSpeed = 4.2
    /// Streets are longer than the straight line between two docks.
    static let streetFactor = 1.3
    /// Finding the dock full, checking the app and picking another one.
    static let discoveryMinutes = 1.5
    /// No single detour is credited with more than this.
    static let maxMinutesPerEvent = 15.0
    /// The same redirect shown again (Check Again, asking Siri twice) counts once.
    static let duplicateWindow: TimeInterval = 30 * 60

    /// Pulling over, unlocking the phone, opening the Citi Bike map and
    /// finding a dock: what each answer by voice saves.
    static let handsFreeMinutes = 1.0
    /// Voice answers this close together (e.g. a Siri answer, then "yes,
    /// direct me") are one check.
    static let handsFreeWindow: TimeInterval = 5 * 60

    /// The rough model shown before a rider has measured savings: about 50
    /// rides a month, each with one hands-free check, and 10% ending at a
    /// full dock with 5 minutes lost each.
    static let typicalMonthlyRides = 50.0
    static let typicalFullDockMinutes = typicalMonthlyRides * 0.10 * 5.0
    static let typicalHandsFreeMinutes = typicalMonthlyRides * handsFreeMinutes
    static var typicalMonthlyMinutes: Double { typicalFullDockMinutes + typicalHandsFreeMinutes }

    /// Minutes saved by going straight to `chosen` instead of to the full
    /// `avoided` dock first. With no starting point, only the ride on from
    /// the full dock is counted.
    static func minutesSaved(from origin: CLLocation?, avoided: CLLocation, chosen: CLLocation) -> Double {
        let extraMeters: CLLocationDistance
        if let origin {
            let without = origin.distance(from: avoided) + avoided.distance(from: chosen)
            extraMeters = max(without - origin.distance(from: chosen), 0)
        } else {
            extraMeters = avoided.distance(from: chosen)
        }
        let minutes = extraMeters * streetFactor / ridingSpeed / 60 + discoveryMinutes
        return min(minutes, maxMinutesPerEvent)
    }

    static func dollars(forMinutes minutes: Double) -> Double {
        minutes * ebikeDollarsPerMinute
    }
}

/// One full dock avoided.
nonisolated struct SavingsEvent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let avoided: AvoidedDock
    let chosenID: String
    let chosenName: String
    let minutes: Double
    /// Where it happened: "siri", "ride_arrival", "place_arrival", "directions", "app".
    let context: String

    var dollars: Double { SavingsModel.dollars(forMinutes: minutes) }
}

/// One dock answer given by voice: a time the rider didn't take out their phone.
nonisolated struct HandsFreeCheck: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    /// "siri", "ride_arrival", "place_arrival" or "directions".
    let context: String
}

nonisolated struct SavingsSummary: Sendable, Equatable {
    var fullDocksAvoided = 0
    var fullDockMinutes = 0.0
    var handsFreeChecks = 0

    var handsFreeMinutes: Double { Double(handsFreeChecks) * SavingsModel.handsFreeMinutes }
    var minutes: Double { fullDockMinutes + handsFreeMinutes }
    var dollars: Double { SavingsModel.dollars(forMinutes: minutes) }

    static func of(
        _ events: [SavingsEvent],
        handsFree checks: [HandsFreeCheck] = [],
        since start: Date? = nil
    ) -> SavingsSummary {
        var summary = SavingsSummary()
        for event in events where start == nil || event.date >= start! {
            summary.fullDocksAvoided += 1
            summary.fullDockMinutes += event.minutes
        }
        summary.handsFreeChecks = checks.filter { start == nil || $0.date >= start! }.count
        return summary
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
