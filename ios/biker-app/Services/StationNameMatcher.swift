//
//  StationNameMatcher.swift
//  Dock Finder
//
//  Fuzzy matching between what a rider says ("Mercer and Bleecker",
//  "West 15th and 6th") and GBFS station names ("Mercer St & Bleecker St",
//  "W 15 St & 6 Ave").
//

import Foundation

nonisolated enum StationNameMatcher {
    /// Scores below this are not treated as a match.
    static let threshold = 600.0

    /// Words that carry no identifying information in a station name.
    private static let fillerWords: Set<String> = [
        "st", "street", "ave", "avenue", "av", "pl", "place", "blvd", "boulevard",
        "rd", "road", "dr", "drive", "and", "the", "station", "dock", "at", "of",
    ]

    private static let replacements: [String: String] = [
        "west": "w", "east": "e", "north": "n", "south": "s",
        "first": "1", "second": "2", "third": "3", "fourth": "4", "fifth": "5", "sixth": "6",
        "seventh": "7", "eighth": "8", "ninth": "9", "tenth": "10", "eleventh": "11", "twelfth": "12",
        "thirteenth": "13", "fourteenth": "14", "fifteenth": "15", "sixteenth": "16", "seventeenth": "17",
        "eighteenth": "18", "nineteenth": "19", "twentieth": "20",
    ]

    /// Lowercased, identifying words only: "W 15 St & 6 Ave" → ["w", "15", "6"].
    static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned)
            .split(separator: " ")
            .map { word -> String in
                let word = String(word)
                if let replacement = replacements[word] { return replacement }
                // "15th" → "15"
                if let digits = word.firstIndex(where: { !$0.isNumber }), digits != word.startIndex,
                   ["st", "nd", "rd", "th"].contains(String(word[digits...])) {
                    return String(word[..<digits])
                }
                return word
            }
            .filter { !fillerWords.contains($0) }
    }

    /// Higher is better. Exact token matches score 10,000.
    static func score(name: String, query: String) -> Double {
        let queryTokens = tokens(query)
        let nameTokens = tokens(name)
        guard !queryTokens.isEmpty, !nameTokens.isEmpty else { return 0 }
        if Set(queryTokens) == Set(nameTokens) { return 10_000 }

        var matched = 0
        var missedNumber = false
        for token in queryTokens {
            if nameTokens.contains(where: { similar($0, token) }) {
                matched += 1
            } else if token.allSatisfy(\.isNumber) {
                missedNumber = true
            }
        }
        var score = Double(matched) / Double(queryTokens.count) * 1_000
            + Double(matched) / Double(nameTokens.count) * 200
        // "W 15 St" must not match "W 16 St".
        if missedNumber { score -= 400 }
        return score
    }

    /// Exact, or one typo apart for longer words ("Bleeker" ≈ "Bleecker").
    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }
}
