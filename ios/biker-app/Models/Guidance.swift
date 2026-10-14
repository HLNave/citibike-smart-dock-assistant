//
//  Guidance.swift
//  Dock Finder
//
//  The rules for spoken turn-by-turn directions to a dock: what the route
//  looks like, where the rider is along it, and what to say next.
//  GuidanceSession runs them against live location; everything here is
//  plain logic so it can be tested without a phone.
//

import CoreLocation
import Foundation

nonisolated struct GuidanceCoordinate: Codable, Sendable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// One maneuver along the route, such as "Turn left onto Bleecker St".
nonisolated struct GuidanceStep: Sendable, Equatable {
    /// As Apple Maps writes it. `Speech.instruction` makes it speakable.
    let instruction: String
    /// Distance along the route from its start to where the maneuver happens.
    let offset: CLLocationDistance
    /// True for the final "The destination is on your left" step, which is
    /// only announced ahead of time; the arrival message covers the rest.
    let isArrival: Bool
}

/// A cycling route to a dock, flattened into one path plus its maneuvers.
nonisolated struct GuidanceRoute: Sendable, Equatable {
    let station: DockStation
    let path: [GuidanceCoordinate]
    /// Distance along the route at each point of `path`.
    let cumulative: [CLLocationDistance]
    /// Maneuvers in order, skipping the empty instruction MapKit gives the start.
    let steps: [GuidanceStep]

    var length: CLLocationDistance { cumulative.last ?? 0 }

    /// Builds a route from MapKit-shaped legs: each leg is the instruction
    /// for the maneuver at its start, plus the points it covers.
    init(station: DockStation, legs: [(instruction: String, points: [GuidanceCoordinate])]) {
        self.station = station
        var path: [GuidanceCoordinate] = []
        var legStarts: [Int] = []
        for leg in legs {
            if let last = path.last, leg.points.first == last {
                legStarts.append(path.count - 1)
                path.append(contentsOf: leg.points.dropFirst())
            } else {
                legStarts.append(leg.points.isEmpty ? max(path.count - 1, 0) : path.count)
                path.append(contentsOf: leg.points)
            }
        }
        if path.isEmpty {
            path = [GuidanceCoordinate(latitude: station.latitude, longitude: station.longitude)]
        }

        var cumulative: [CLLocationDistance] = [0]
        for index in path.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + path[index - 1].location.distance(from: path[index].location))
        }

        let lastLeg = legs.indices.last
        steps = zip(legs.indices, legs).compactMap { index, leg in
            let instruction = leg.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { return nil }
            let lowered = instruction.lowercased()
            return GuidanceStep(
                instruction: instruction,
                offset: cumulative[min(legStarts[index], cumulative.count - 1)],
                isArrival: index == lastLeg && (lowered.contains("destination") || lowered.hasPrefix("arrive"))
            )
        }
        self.path = path
        self.cumulative = cumulative
    }

    /// The closest point on the route to `location`, searching from
    /// `segment` onward and no more than `lookahead` past `along`, so a
    /// route that doubles back on itself can't make the rider jump ahead.
    func locate(
        _ location: CLLocation,
        from segment: Int,
        along: CLLocationDistance,
        lookahead: CLLocationDistance = 400
    ) -> (segment: Int, along: CLLocationDistance, distance: CLLocationDistance) {
        let point = GuidanceCoordinate(location.coordinate)
        guard path.count >= 2 else {
            return (0, 0, location.distance(from: path[0].location))
        }
        var best = (segment: segment, along: along, distance: CLLocationDistance.infinity)
        for index in max(segment - 1, 0)..<(path.count - 1) {
            if cumulative[index] > along + lookahead { break }
            let (fraction, distance) = Self.project(point, onto: path[index], path[index + 1])
            if distance < best.distance {
                let length = cumulative[index + 1] - cumulative[index]
                best = (index, cumulative[index] + fraction * length, distance)
            }
        }
        return best
    }

    /// Where `point` falls along the segment `a`–`b` (0 to 1) and how far
    /// it is from it, in meters. A flat projection is accurate enough over
    /// the length of a city block.
    static func project(
        _ point: GuidanceCoordinate,
        onto a: GuidanceCoordinate,
        _ b: GuidanceCoordinate
    ) -> (fraction: Double, distance: CLLocationDistance) {
        let metersPerDegree = 111_320.0
        let scale = cos(a.latitude * .pi / 180)
        let bx = (b.longitude - a.longitude) * scale * metersPerDegree
        let by = (b.latitude - a.latitude) * metersPerDegree
        let px = (point.longitude - a.longitude) * scale * metersPerDegree
        let py = (point.latitude - a.latitude) * metersPerDegree
        let lengthSquared = bx * bx + by * by
        let fraction = lengthSquared > 0 ? min(max((px * bx + py * by) / lengthSquared, 0), 1) : 0
        let dx = px - fraction * bx
        let dy = py - fraction * by
        return (fraction, (dx * dx + dy * dy).squareRoot())
    }
}

/// Where the rider is along a route, and what to say as they ride it.
nonisolated struct GuidanceProgress: Sendable, Equatable {
    /// Within this of the dock, the rider has arrived.
    static let arrivalRadius: CLLocationDistance = 30
    /// "In 500 feet, turn left onto Bleecker Street."
    static let prepareDistance: CLLocationDistance = 150
    /// "Turn left onto Bleecker Street."
    static let turnNowDistance: CLLocationDistance = 35
    /// A maneuver this far behind the rider was missed or already made.
    static let passedSlack: CLLocationDistance = 10
    /// Farther than this from the route counts as off it…
    static let offRouteDistance: CLLocationDistance = 45
    /// …for this many fixes in a row before re-routing.
    static let offRouteFixes = 2
    /// Fixes less accurate than this are ignored; Manhattan's tall
    /// buildings produce plenty of them.
    static let maxUsableAccuracy: CLLocationAccuracy = 65

    enum Event: Sendable, Equatable {
        case say(String)
        case arrived
        case offRoute
    }

    let route: GuidanceRoute
    /// Distance covered along the route.
    private(set) var along: CLLocationDistance = 0
    private(set) var segment = 0
    /// Index into `route.steps` of the next maneuver.
    private(set) var nextStep = 0
    private var preparedSteps: Set<Int> = []
    private var offRouteCount = 0

    init(route: GuidanceRoute) {
        self.route = route
    }

    var remaining: CLLocationDistance { max(route.length - along, 0) }

    var nextManeuver: GuidanceStep? {
        nextStep < route.steps.count ? route.steps[nextStep] : nil
    }

    var distanceToNextManeuver: CLLocationDistance? {
        nextManeuver.map { max($0.offset - along, 0) }
    }

    /// What to say when guidance starts: how far it is, then the first
    /// maneuver. "0.3 miles to West 4th and Mercer. Head north on 6th Avenue."
    mutating func opening() -> String {
        var parts = ["\(Speech.sentence(Speech.length(route.length))) to \(route.station.spokenName)."]
        if let step = nextManeuver, let distance = distanceToNextManeuver {
            let instruction = Speech.instruction(step.instruction)
            if distance <= Self.turnNowDistance, !step.isArrival {
                parts.append(Speech.period(instruction))
                nextStep += 1
            } else {
                parts.append(Speech.period("In \(Speech.length(distance)), \(Speech.lowercasingFirst(instruction))"))
                if distance <= Self.prepareDistance { preparedSteps.insert(nextStep) }
            }
        }
        return parts.joined(separator: " ")
    }

    /// Advances along the route and returns anything to say or do.
    mutating func update(at location: CLLocation) -> [Event] {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maxUsableAccuracy else {
            return []
        }
        if location.distance(from: route.station.location) <= Self.arrivalRadius {
            return [.arrived]
        }

        let match = route.locate(location, from: segment, along: along)
        guard match.distance <= Self.offRouteDistance else {
            offRouteCount += 1
            if offRouteCount >= Self.offRouteFixes {
                offRouteCount = 0
                return [.offRoute]
            }
            return []
        }
        offRouteCount = 0
        segment = match.segment
        along = max(along, match.along)

        // Skip maneuvers the rider is already past (a GPS gap, or a turn
        // taken early).
        while let step = nextManeuver, step.offset < along - Self.passedSlack {
            nextStep += 1
        }
        guard let step = nextManeuver, let distance = distanceToNextManeuver else { return [] }

        let instruction = Speech.instruction(step.instruction)
        if distance <= Self.turnNowDistance {
            nextStep += 1
            return step.isArrival ? [] : [.say(Speech.period(instruction))]
        }
        if distance <= Self.prepareDistance, !preparedSteps.contains(nextStep) {
            preparedSteps.insert(nextStep)
            return [.say(Speech.period("In \(Speech.length(distance)), \(Speech.lowercasingFirst(instruction))"))]
        }
        return []
    }
}

/// What a mid-ride check of the target dock found.
nonisolated enum DockCheckOutcome: Sendable, Equatable {
    /// Still has room: this many open docks.
    case fine(docksOpen: Int)
    /// Filled up or closed; head to `alternative` instead.
    case switchTo(DockStation, problem: StationProblem)
    /// Filled up or closed, and nothing nearby has room.
    case noAlternative(problem: StationProblem, docksOpen: Int)
    /// The station is no longer in Citi Bike's list.
    case unknown

    static func check(_ stationID: String, in network: StationNetwork) -> DockCheckOutcome {
        guard let snapshot = network.station(id: stationID) else { return .unknown }
        guard let problem = network.problem(with: snapshot) else {
            return .fine(docksOpen: snapshot.openDocks)
        }
        let alternative = network.returnableStations(
            around: snapshot.location,
            within: StationNetwork.nearbyRadius,
            excluding: stationID
        ).first
        guard let alternative else {
            return .noAlternative(problem: problem, docksOpen: snapshot.openDocks)
        }
        return .switchTo(alternative, problem: problem)
    }
}
