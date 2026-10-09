//
//  RequestParsing.swift
//  Dock Finder
//
//  Understands free-form requests ("find me a dock near Union Square",
//  "is Mercer and Bleecker full?") on device. Two parsers run in order:
//  simple phrase rules that work on every iPhone, then Apple's on-device
//  language model where Apple Intelligence is available. Only requests
//  neither understands go to the n8n backend.
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
}

nonisolated protocol RequestParsing: Sendable {
    /// How an answer built from this parser's result is labeled.
    var answerSource: DockAnswer.Source { get }
    /// `nil` when the request isn't understood.
    func parse(_ text: String) async -> ParsedRequest?
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

        // "How many docks at Mercer and Bleecker" is about one station, so it
        // is checked before the citywide phrases.
        if let target = capture(#"^how many (?:docks|bikes|spots|spaces)(?: are)?(?: open| available| left| free)? (?:at|on)\s+(.+)$"#, in: request) {
            return .station(target)
        }
        if citywidePhrases.contains(where: request.contains) {
            return .citywide
        }
        // Short answers to "Where are you headed, or which station?".
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

/// Handles a bare answer to "Where are you headed, or which station?", such
/// as "school" (a saved place) or "Mercer and Bleecker" (a station), which
/// the phrase rules can't classify without knowing the rider's places and
/// the station list.
nonisolated struct ShortAnswerParser: RequestParsing {
    var savedPlaces: [SavedPlace]
    var service: DockFinderService

    var answerSource: DockAnswer.Source { .onDevice }

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
    case unknown
}

@Generable
nonisolated struct ModelParsedRequest {
    @Guide(description: "nearMe: a dock near the rider's current location. place: a dock near a named place, address, landmark, business or neighborhood. station: whether one named Citi Bike station has room. citywide: totals for the whole Citi Bike system. unknown: anything else.")
    var kind: ModelRequestKind

    @Guide(description: "For place: what to search for on a map of New York City, such as 'Union Square' or '44 West 4th Street'. Otherwise empty.")
    var place: String

    @Guide(description: "For station: the station name as said, such as 'Mercer and Bleecker'. Otherwise empty.")
    var station: String
}

/// Runs only on iPhones with Apple Intelligence turned on (iPhone 15 Pro
/// and newer). Everywhere else it returns `nil` and the request moves on.
nonisolated struct OnDeviceModelParser: RequestParsing {
    var answerSource: DockAnswer.Source { .onDeviceModel }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private static let instructions = """
        You classify a Citi Bike rider's request in New York City. Do not answer it. \
        Choose the kind and fill in the place or station field. Use empty strings for fields that don't apply.
        """

    func parse(_ text: String) async -> ParsedRequest? {
        guard Self.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let parsed = try await session.respond(to: text, generating: ModelParsedRequest.self).content
            let place = parsed.place.trimmingCharacters(in: .whitespacesAndNewlines)
            let station = parsed.station.trimmingCharacters(in: .whitespacesAndNewlines)
            switch parsed.kind {
            case .nearMe: return .nearMe
            case .place: return place.isEmpty ? nil : .place(place)
            case .station: return station.isEmpty ? nil : .station(station)
            case .citywide: return .citywide
            case .unknown: return nil
            }
        } catch {
            return nil
        }
    }
}
