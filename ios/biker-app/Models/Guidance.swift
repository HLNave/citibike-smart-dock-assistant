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

    /// Which way the route sets off, from its first 25 m: "north", "east",
    /// "south" or "west". Four directions match how riders describe
    /// Manhattan's tilted grid: avenues run north–south, streets east–west.
    var startHeading: String? {
        guard path.count >= 2 else { return nil }
        let end = cumulative.firstIndex { $0 >= 25 } ?? (path.count - 1)
        guard end > 0, path[end] != path[0] else { return nil }
        return Self.compassPoint(Self.bearing(from: path[0], to: path[end]))
    }

    /// Degrees clockwise from true north.
    static func bearing(from a: GuidanceCoordinate, to b: GuidanceCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x) * 180 / .pi
    }

    static func compassPoint(_ bearing: Double) -> String {
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return ["north", "east", "south", "west"][Int((normalized + 45) / 90) % 4]
    }

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
            let isArrival = index == lastLeg && (lowered.contains("destination") || lowered.hasPrefix("arrive"))
            return GuidanceStep(
                instruction: instruction,
                // "The dock is on your right" belongs at the dock itself, not
                // where Maps' last step starts (which can be a block or more
                // back), or it's said far too early.
                offset: isArrival ? (cumulative.last ?? 0) : cumulative[min(legStarts[index], cumulative.count - 1)],
                isArrival: isArrival
            )
        }
        self.path = path
        self.cumulative = cumulative
    }

    /// The point `distance` along the route.
    func location(at distance: CLLocationDistance) -> CLLocation {
        guard path.count >= 2 else { return path[0].location }
        let index = segment(containing: distance)
        let start = cumulative[index]
        let length = cumulative[index + 1] - start
        let fraction = length > 0 ? min(max((distance - start) / length, 0), 1) : 0
        let a = path[index], b = path[index + 1]
        return CLLocation(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// The index of the path segment that `distance` along the route falls in.
    func segment(containing distance: CLLocationDistance) -> Int {
        guard path.count >= 2 else { return 0 }
        let index = cumulative.lastIndex { $0 <= distance } ?? 0
        return min(index, path.count - 2)
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
    /// How far ahead along the route a fix may match before the rider has
    /// moved: enough for GPS jitter, not enough to land on a later street
    /// that loops back past the start.
    static let initialLookahead: CLLocationDistance = 60
    /// The fastest a rider can plausibly move along the route (a fast
    /// e-bike, about 32 km/h)…
    static let maxSpeed: CLLocationSpeed = 9
    /// …plus this, per fix. A fix further ahead than that is GPS error
    /// (common between Manhattan's tall buildings), and believing it made
    /// turns get announced a block early.
    static let advanceSlack: CLLocationDistance = 15
    /// A maneuver is only skipped silently (missed, or taken early) on a
    /// fix at least this accurate; otherwise it's said, late.
    static let skipAccuracy: CLLocationAccuracy = 25
    /// A maneuver is only announced when the rider is really that close to
    /// it in a straight line, give or take the fix's accuracy (at least
    /// this) and this much more. Distance along the route can still run
    /// ahead of the rider; this keeps the voice from following it.
    static let minimumSlack: CLLocationDistance = 20
    static let announceMargin: CLLocationDistance = 30
    /// A fix this close to the route sits on the street it matched. When
    /// nothing within the lookahead is this close but a later street is,
    /// the rider is already past a turn.
    static let onStreetDistance: CLLocationDistance = 30

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
    /// The last fix that matched the route, and when it was taken.
    private var lastFix: GuidanceCoordinate?
    private var lastFixTime: Date?
    /// How far along the rider can be vouched for: it only advances as fast
    /// as they're actually riding. `along` may run up to `advanceSlack`
    /// past it, once, rather than per fix.
    private var trustedAlong: CLLocationDistance = 0

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

    /// What the rider is doing now, shown above the next turn: "Head north
    /// on 6th Avenue" before the first turn, then "On Bleecker Street"
    /// after turning onto it.
    var currentInstruction: String? {
        guard nextStep > 0, nextStep - 1 < route.steps.count else {
            return route.startHeading.map { "Head \($0)" }
        }
        let passed = route.steps[nextStep - 1]
        guard !passed.isArrival else { return nil }
        let instruction = Speech.instruction(passed.instruction)
        if passed.offset <= Self.turnNowDistance {
            // The start ("Head north on 6th Avenue", "Start on 6th Avenue").
            return Self.addingHeading(route.startHeading, to: instruction)
        }
        return Self.street(after: instruction)
    }

    /// "Turn right onto Bleecker Street" → "On Bleecker Street".
    static func street(after instruction: String) -> String {
        guard let match = instruction.range(of: #"\b(?:onto|on)\s+(.+?)\.?$"#, options: [.regularExpression, .caseInsensitive]) else {
            return instruction
        }
        let phrase = instruction[match]
        guard let space = phrase.firstIndex(where: \.isWhitespace) else { return instruction }
        let street = phrase[space...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return street.isEmpty ? instruction : "On \(street)"
    }

    /// What to say when guidance starts: how far it is, which way to set
    /// off, then the first maneuver. "0.3 miles to West 4th and Mercer.
    /// Head north on 6th Avenue." / "… Head east, then in 300 feet, turn
    /// left onto 7th Avenue."
    mutating func opening() -> String {
        var parts = ["\(Speech.sentence(Speech.length(route.length))) to \(route.station.spokenName)."]
        let heading = route.startHeading
        guard let step = nextManeuver, let distance = distanceToNextManeuver else {
            if let heading { parts.append("Head \(heading).") }
            return parts.joined(separator: " ")
        }
        let instruction = Speech.instruction(step.instruction)
        if distance <= Self.turnNowDistance, !step.isArrival {
            parts.append(Speech.period(Self.addingHeading(heading, to: instruction)))
            nextStep += 1
        } else {
            let next = "in \(Speech.length(distance)), \(Speech.lowercasingFirst(instruction))"
            parts.append(Speech.period(heading.map { "Head \($0), then \(next)" } ?? Speech.sentence(next)))
            if distance <= Self.prepareDistance { preparedSteps.insert(nextStep) }
        }
        return parts.joined(separator: " ")
    }

    /// "Start on West 14th Street" → "Head east on West 14th Street". An
    /// instruction that already says which way ("Head north on…", "Turn
    /// left onto…") is left alone.
    static func addingHeading(_ heading: String?, to instruction: String) -> String {
        guard let heading else { return instruction }
        let alreadyDirected = #"^(?:(?:Head|Go)\s+(?:north|south|east|west)|(?:Turn|Bear|Keep|Slight|Make|Take)\b)"#
        if instruction.range(of: alreadyDirected, options: [.regularExpression, .caseInsensitive]) != nil {
            return instruction
        }
        guard let lead = instruction.range(of: #"^(?:Start|Proceed|Continue|Go|Head)(?:\s+(?:on|along|onto|to))?\s+"#, options: [.regularExpression, .caseInsensitive]) else {
            return instruction
        }
        let street = instruction[lead.upperBound...]
        if street.lowercased().hasPrefix("the route") {
            return "Head \(heading)"
        }
        return "Head \(heading) on \(street)"
    }

    /// Advances along the route and returns anything to say or do.
    mutating func update(at location: CLLocation) -> [Event] {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maxUsableAccuracy else {
            return []
        }
        if location.distance(from: route.station.location) <= Self.arrivalRadius {
            return [.arrived]
        }

        // Only look as far ahead as the rider could have ridden since the
        // last fix. Short routes around Manhattan's one-way blocks often
        // pass back near where they started; matching the rider to that
        // later street skipped every turn but the last.
        let moved = lastFix.map { location.distance(from: $0.location) }
        let lookahead = moved.map { max($0 * 2 + 40, Self.initialLookahead) } ?? Self.initialLookahead
        var match = route.locate(location, from: segment, along: along, lookahead: lookahead)
        if match.distance > Self.onStreetDistance {
            // Nothing within reach fits well, but a later street might: a
            // GPS gap, a turn taken early, or guidance started past the
            // first turn.
            let ahead = route.locate(location, from: segment, along: along)
            if ahead.distance <= Self.onStreetDistance { match = ahead }
        }
        guard match.distance <= Self.offRouteDistance else {
            offRouteCount += 1
            if offRouteCount >= Self.offRouteFixes {
                offRouteCount = 0
                return [.offRoute]
            }
            return []
        }
        offRouteCount = 0
        var reached = match.along
        // No further along than the rider could have ridden since the last
        // fix. (Fixes with no time between them, as in tests, aren't capped.)
        if let lastFixTime, location.timestamp > lastFixTime {
            let elapsed = location.timestamp.timeIntervalSince(lastFixTime)
            // The fix's own speed (from the GPS Doppler shift, reliable even
            // when its position isn't) when it has one, so fixes drifting
            // ahead while the rider waits at a light can't creep forward.
            let speed = location.speed >= 0 ? min(max(location.speed * 1.5, 2), Self.maxSpeed) : Self.maxSpeed
            trustedAlong = max(trustedAlong, min(match.along, trustedAlong + speed * elapsed))
            reached = min(reached, trustedAlong + Self.advanceSlack)
        } else {
            trustedAlong = max(trustedAlong, match.along)
        }
        lastFix = GuidanceCoordinate(location.coordinate)
        lastFixTime = location.timestamp
        if reached > along {
            along = reached
            segment = reached < match.along ? route.segment(containing: reached) : match.segment
        }

        // Skip maneuvers the rider is clearly past (a GPS gap, or a turn
        // taken early). On a rough fix, the turn is said instead, below.
        if location.horizontalAccuracy <= Self.skipAccuracy {
            while let step = nextManeuver, step.offset < along - Self.passedSlack {
                nextStep += 1
            }
        }
        guard let step = nextManeuver, let distance = distanceToNextManeuver else { return [] }

        let instruction = Speech.instruction(step.instruction)
        let point = step.isArrival ? route.station.location : route.location(at: step.offset)
        let straight = location.distance(from: point)
        let slack = max(location.horizontalAccuracy, Self.minimumSlack) + Self.announceMargin
        if distance <= Self.turnNowDistance {
            guard straight <= Self.turnNowDistance + slack else { return [] }
            nextStep += 1
            return step.isArrival ? [] : [.say(Speech.period(instruction))]
        }
        if distance <= Self.prepareDistance, !preparedSteps.contains(nextStep) {
            guard straight <= Self.prepareDistance + slack else { return [] }
            preparedSteps.insert(nextStep)
            // The straight line is never longer than the way there, so it's
            // the honest figure when the two disagree.
            return [.say(Speech.period("In \(Speech.length(max(distance, straight))), \(Speech.lowercasingFirst(instruction))"))]
        }
        return []
    }
}

/// What a mid-ride check of the target dock found.
nonisolated enum DockCheckOutcome: Sendable, Equatable {
    /// At or below this many open docks, and fewer than last time, the dock
    /// is "filling up".
    static let fillingUpDocks = 5

    /// Said after each check that found room: "West 4th and Mercer still
    /// has 8 docks open." / "West 4th and Mercer is filling up, 3 docks open."
    static func statusLine(for dockName: String, docksOpen: Int, previously: Int?) -> String {
        let name = Speech.sentence(dockName)
        if docksOpen <= fillingUpDocks, let previously, docksOpen < previously {
            return "\(name) is filling up, \(Speech.docksOpen(docksOpen))."
        }
        return "\(name) still has \(Speech.docksOpen(docksOpen))."
    }

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
