//
//  RequestParsing.swift
//  Dock Finder
//
//  Understands free-form requests ("find me a dock near Union Square",
//  "is Mercer and Bleecker full?", "direct me to school") on device.
//  Where Apple Intelligence is available, Apple's on-device language model
//  reads the request first and picks the action; the simple phrase rules
//  (which work on every iPhone) handle it otherwise, or when the model
//  can't tell. Only requests neither understands go to the n8n backend.
//

import Foundation
import FoundationModels

/// What the rider asked for, in terms the on-device features can answer.
nonisolated enum ParsedRequest: Sendable, Equatable {
    case nearMe
    /// A place name or address. May also be a saved place ("school").
    case place(String)
    /// A station name. May also be "my school dock" / "my usual dock".
    case station(String)
    case citywide
    /// "Start a ride to school": watch for arrival and say where to dock.
    /// Empty when no destination was named.
    case startRide(String)
    case endRide
    /// "My school dock is Mercer and Bleecker".
    case setUsualDock(place: String, station: String)
    /// "Save this spot as gym".
    case savePlace(String)
    /// "Take me there": turn-by-turn guidance to the dock just mentioned.
    case directions
    /// "Direct me to school": turn-by-turn guidance to the best dock at a
    /// saved place, address or landmark.
    case directionsTo(String)
    /// "Stop directions".
    case stopDirections
}

nonisolated protocol RequestParsing: Sendable {
    /// How an answer built from this parser's result is labeled.
    var answerSource: DockAnswer.Source { get }
    /// Which step this parser is, for usage data. By default, from `answerSource`.
    var answeredBy: DockAnswer.Step { get }
    /// `nil` when the request isn't understood.
    func parse(_ text: String) async -> ParsedRequest?
}

extension RequestParsing {
    nonisolated var answeredBy: DockAnswer.Step {
        switch answerSource {
        case .onDevice: .phraseRules
        case .onDeviceModel: .appleIntelligence
        case .server: .server
        }
    }
}

// MARK: - Phrase rules

nonisolated struct KeywordRequestParser: RequestParsing {
    var answerSource: DockAnswer.Source { .onDevice }

    private static let selfReferences: Set<String> = [
        "me", "here", "us", "myself", "my location", "my current location", "where i am", "where i'm at", "where im at",
    ]
    private static let nearMePhrases = [
        "near me", "nearby", "near here", "around me", "around here", "close by", "closest dock", "nearest dock",
        "closest station", "nearest station", "where i am", "my location",
    ]
    private static let citywidePhrases = [
        "citywide", "city wide", "whole system", "whole network", "entire system", "across the city",
        "system status", "network status", "how many bikes are out", "how many bikes are available",
        "how many bikes are there", "how many docks are open", "how many open docks", "how busy is citi bike",
    ]

    func parse(_ text: String) async -> ParsedRequest? {
        Self.parse(text)
    }

    static func parse(_ text: String) -> ParsedRequest? {
        let request = normalize(text)
        guard !request.isEmpty else { return nil }

        // Directions first: "take me to the dock" isn't a ride to a place
        // called "the dock". Then rides and saved-place edits, since "start
        // a ride to the park near my office" would otherwise read as a
        // place search.
        if let guidance = parseGuidance(request) {
            return guidance
        }
        if let ride = parseRide(request) {
            return ride
        }
        if let edit = parsePlaceEdit(request) {
            return edit
        }

        // "How many docks at Mercer and Bleecker" is about one station, so it
        // is checked before the citywide phrases.
        if let target = capture(#"^how many (?:docks|bikes|spots|spaces)(?: are)?(?: open| available| left| free)? (?:at|on)\s+(.+)$"#, in: request) {
            return .station(target)
        }
        if citywidePhrases.contains(where: request.contains) {
            return .citywide
        }
        // Short answers: "here", "nearest".
        if selfReferences.contains(request) || ["nearest", "closest", "nearest one", "closest one"].contains(request) {
            return .nearMe
        }
        if let target = capture(#"\b(?:near|nearest to|closest to|close to|next to|around|by)\s+(.+)$"#, in: request) {
            return selfReferences.contains(target) ? .nearMe : .place(target)
        }
        if nearMePhrases.contains(where: request.contains) {
            return .nearMe
        }
        let stationPatterns = [
            #"^(?:is|are)\s+(?:the\s+)?(.+?)\s+(?:station\s+|dock\s+)?(?:full|empty|open|closed|available|busy|packed)\b"#,
            #"^(?:does|do)\s+(?:the\s+)?(.+?)\s+have\s+(?:room|space|docks|spots|any docks|bikes)\b"#,
            #"^(?:check|check on|status of|how is|how's|hows|what about|look up)\s+(?:the\s+)?(?:station\s+at\s+)?(.+?)(?:\s+station)?$"#,
        ]
        for pattern in stationPatterns {
            if let target = capture(pattern, in: request) {
                return .station(target)
            }
        }
        // "Find me a dock", "where can I park" with no place named.
        if request.range(of: #"\b(dock|docks|park|return|drop off|parking)\b"#, options: .regularExpression) != nil {
            return .nearMe
        }
        return nil
    }

    private static let directionEndings: Set<String> = [
        "stop directions", "stop the directions", "cancel directions", "cancel the directions", "end directions",
        "stop guiding", "stop guiding me", "stop navigation", "stop the navigation", "stop navigating",
    ]

    private static let directionRequests = [
        #"^(?:yes,? )?(?:direct|guide|take|navigate|bring|lead) me(?: there| to it| to that dock| to the dock| to that station| to the station)?$"#,
        #"^(?:get |give me |start )?directions(?: there| to it| to that dock| to the dock)?$"#,
    ]

    private static func parseGuidance(_ request: String) -> ParsedRequest? {
        if directionEndings.contains(request) {
            return .stopDirections
        }
        if directionRequests.contains(where: { request.range(of: $0, options: .regularExpression) != nil }) {
            return .directions
        }
        let toPlace = [
            #"^(?:direct|guide|navigate|lead|bring) me to (.+)$"#,
            #"^(?:get |give me |start )?(?:directions|guidance) to (.+)$"#,
        ]
        for pattern in toPlace {
            if let place = capture(pattern, in: request) {
                return .directionsTo(place)
            }
        }
        return nil
    }

    private static let rideEndings: Set<String> = [
        "end ride", "end my ride", "end the ride", "stop ride", "stop my ride", "stop the ride",
        "cancel ride", "cancel my ride", "cancel the ride", "finish ride", "finish my ride",
        "i'm done riding", "im done riding", "i am done riding", "end trip", "cancel trip",
    ]

    private static func parseRide(_ request: String) -> ParsedRequest? {
        if rideEndings.contains(request) {
            return .endRide
        }
        if request.range(of: #"^(?:start|begin)(?: a| my| the)? (?:ride|trip)$"#, options: .regularExpression) != nil {
            return .startRide("")
        }
        let patterns = [
            #"^(?:start|begin)(?: a| my| the)? (?:ride|trip)(?: now)? (?:to|for|towards) (.+)$"#,
            #"^(?:i'm|im|i am) (?:riding|biking|cycling|heading|going) (?:to|towards) (.+)$"#,
            #"^(?:ride|bike|riding|biking) (?:to|towards) (.+)$"#,
            #"^(?:take me|navigate|guide me) to (.+)$"#,
        ]
        for pattern in patterns {
            if let destination = capture(pattern, in: request) {
                return .startRide(destination)
            }
        }
        return nil
    }

    /// Words that make "my school dock is ___" a status question, not a setting.
    private static let statusWords: Set<String> = ["full", "empty", "open", "closed", "available", "busy", "packed", "free"]

    private static func parsePlaceEdit(_ request: String) -> ParsedRequest? {
        if let groups = captures(#"^(?:my|the) (.+?) dock is (?:now )?(.+)$"#, in: request) {
            // "My school dock is full?" asks about the dock instead of setting it.
            return statusWords.contains(groups[1])
                ? .station("my \(groups[0]) dock")
                : .setUsualDock(place: groups[0], station: groups[1])
        }
        if let groups = captures(#"^(?:set|change|make) (?:my |the )?(.+?) dock (?:to|as) (.+)$"#, in: request) {
            return .setUsualDock(place: groups[0], station: groups[1])
        }
        if let groups = captures(#"^(?:use|make) (.+?) (?:as )?my (.+?) dock$"#, in: request) {
            return .setUsualDock(place: groups[1], station: groups[0])
        }
        if let name = capture(#"^(?:save|remember|add) (?:this place|this spot|this location|here|my location|my current location|where i am)(?: as| called)? (.+)$"#, in: request) {
            return .savePlace(name)
        }
        return nil
    }

    /// The destination in an answer to "Where are you heading?": "to
    /// school" → "school", "I'm going to Union Square" → "union square".
    static func destination(from answer: String) -> String {
        let request = normalize(answer)
        if case .startRide(let destination)? = parseRide(request), !destination.isEmpty {
            return destination
        }
        let prefixes = [
            "i'm heading to ", "im heading to ", "i am heading to ", "i'm going to ", "im going to ", "i am going to ",
            "i'm riding to ", "im riding to ", "heading to ", "going to ", "riding to ", "towards ", "toward ", "to ",
        ]
        for prefix in prefixes where request.hasPrefix(prefix) {
            return String(request.dropFirst(prefix.count))
        }
        return request
    }

    /// Lowercased, without "hey siri"/"please" and trailing punctuation.
    static func normalize(_ text: String) -> String {
        var request = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!,")))
        for prefix in ["hey siri ", "hey siri, ", "please ", "can you ", "could you "] where request.hasPrefix(prefix) {
            request.removeFirst(prefix.count)
        }
        for suffix in [" please", " right now", " now"] where request.hasSuffix(suffix) {
            request.removeLast(suffix.count)
        }
        // Dictation often writes "dock" as "doc", since they sound the same.
        return request.split(whereSeparator: \.isWhitespace)
            .map { homophones[String($0)] ?? String($0) }
            .joined(separator: " ")
    }

    private static let homophones = ["doc": "dock", "docs": "docks", "doc's": "dock's"]

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
            Range(match.range(at: index), in: text).map {
                text[$0].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }
        return groups.contains(where: \.isEmpty) ? nil : groups
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }
}

// MARK: - Short answers

/// Handles a bare answer to "What do you need?", such as "school" (a saved
/// place) or "Mercer and Bleecker" (a station), which
/// the phrase rules can't classify without knowing the rider's places and
/// the station list.
nonisolated struct ShortAnswerParser: RequestParsing {
    var savedPlaces: [SavedPlace]
    var service: DockFinderService

    var answerSource: DockAnswer.Source { .onDevice }
    var answeredBy: DockAnswer.Step { .shortAnswer }

    func parse(_ text: String) async -> ParsedRequest? {
        let request = KeywordRequestParser.normalize(text)
        guard !request.isEmpty else { return nil }
        if savedPlaces.contains(where: { $0.matches(request) }) {
            return .place(request)
        }
        guard let directory = try? await service.stationDirectory(),
              let station = StationNameMatcher.confidentMatch(for: request, in: directory)
        else { return nil }
        return .station(station.stationID)
    }
}

// MARK: - Apple's on-device language model

@Generable
nonisolated enum ModelRequestKind {
    case nearMe
    case place
    case station
    case citywide
    case startRide
    case endRide
    case directions
    case directionsToPlace
    case stopDirections
    case unknown
}

@Generable
nonisolated struct ModelParsedRequest {
    @Guide(description: "nearMe: the rider wants a dock with room near where they are now. place: the rider wants to know where to dock near a named place, saved place, address, landmark or neighborhood. station: whether one named Citi Bike station has room. citywide: totals for the whole Citi Bike system. startRide: the rider is setting off to a destination and wants to be told where to dock when they get close. endRide: stop or cancel the current ride. directions: turn-by-turn directions to the dock just mentioned, with no place named ('take me there', 'direct me'). directionsToPlace: turn-by-turn directions to a dock at a named place ('direct me to school', 'how do I get to a dock by Union Square'). stopDirections: stop the turn-by-turn directions. unknown: anything else.")
    var kind: ModelRequestKind

    @Guide(description: "For place, startRide or directionsToPlace: the place exactly as one of the rider's saved place names if it's one of them, otherwise as said or as a New York City address or landmark, such as 'Union Square' or '44 West 4th Street'. Otherwise empty.")
    var place: String

    @Guide(description: "For station: the station name as said, such as 'Mercer and Bleecker'. Otherwise empty.")
    var station: String
}

/// Runs first, on iPhones with Apple Intelligence turned on (iPhone 15
/// Pro and newer), so requests are understood however they're worded.
/// Everywhere else, or if the model can't tell or takes too long, it
/// returns `nil` and the phrase rules handle the request.
nonisolated struct OnDeviceModelParser: RequestParsing {
    /// What the rider calls their saved places, so "my office" or "Stern"
    /// is understood as one.
    var savedPlaceNames: [String] = []
    /// Siri gives an action only a few seconds, and the phrase rules still
    /// follow, so a slow model gives up.
    var timeLimit: Duration = .seconds(4)

    var answerSource: DockAnswer.Source { .onDeviceModel }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func instructions(savedPlaceNames: [String]) -> String {
        var text = """
            You turn a Citi Bike rider's request in New York City into one action for the Dock Finder app. \
            Do not answer it. Choose the kind and fill in the place or station field; use empty strings for fields that don't apply. \
            "Dock" may be written "doc".
            """
        if !savedPlaceNames.isEmpty {
            text += " The rider's saved places are: \(savedPlaceNames.joined(separator: ", ")). Treat those names, with or without \"my\", as places."
        }
        return text
    }

    func parse(_ text: String) async -> ParsedRequest? {
        guard Self.isAvailable else { return nil }
        let instructions = Self.instructions(savedPlaceNames: savedPlaceNames)
        return await withTimeLimit(timeLimit) {
            await Self.classify(text, instructions: instructions)
        }
    }

    private static func classify(_ text: String, instructions: String) async -> ParsedRequest? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let parsed = try await session.respond(to: text, generating: ModelParsedRequest.self).content
            return request(from: parsed)
        } catch {
            return nil
        }
    }

    static func request(from parsed: ModelParsedRequest) -> ParsedRequest? {
        let place = parsed.place.trimmingCharacters(in: .whitespacesAndNewlines)
        let station = parsed.station.trimmingCharacters(in: .whitespacesAndNewlines)
        switch parsed.kind {
        case .nearMe: return .nearMe
        case .place: return place.isEmpty ? nil : .place(place)
        case .station: return station.isEmpty ? nil : .station(station)
        case .citywide: return .citywide
        case .startRide: return .startRide(place)
        case .endRide: return .endRide
        case .directions: return .directions
        case .directionsToPlace: return place.isEmpty ? .directions : .directionsTo(place)
        case .stopDirections: return .stopDirections
        case .unknown: return nil
        }
    }
}
