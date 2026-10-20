//
//  Speech.swift
//  Dock Finder
//
//  Turns station data into short sentences Siri can read aloud cleanly.
//  Ported from the n8n workflow's `make-it-speakable` node so the app and
//  the backend sound the same.
//

import CoreLocation
import Foundation

nonisolated enum Speech {
    /// Rewrites a GBFS station name the way New Yorkers say it, so Siri
    /// doesn't read "St" as "Saint": "W 15 St & 6 Ave" → "West 15th and 6th".
    static func stationName(_ name: String) -> String {
        var text = name.replacingOccurrences(of: "&", with: " and ")
        text = replace(#"\bE\b(?=\s+\d)"#, in: text) { _ in "East" }
        text = replace(#"\bW\b(?=\s+\d)"#, in: text) { _ in "West" }
        text = replace(#"\b(\d+)\s+(St|Ave)\b"#, in: text) { groups in
            Int(groups[1]).map(ordinal) ?? groups[0]
        }
        // Drop a trailing street suffix unless another word of the name follows it.
        text = replace(#"\s+(St|Ave|Pl|Blvd|Rd|Dr)\b(?!\s+[A-Z0-9])"#, in: text) { _ in "" }
        text = replace(#"\bAve\b"#, in: text) { _ in "Avenue" }
        text = replace(#"\bPl\b"#, in: text) { _ in "Place" }
        text = replace(#"\bBlvd\b"#, in: text) { _ in "Boulevard" }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "1 dock open" / "12 docks open".
    static func docksOpen(_ count: Int) -> String {
        count == 1 ? "1 dock open" : "\(count) docks open"
    }

    /// "1 bike" / "4 bikes".
    static func bikes(_ count: Int) -> String {
        count == 1 ? "1 bike" : "\(count) bikes"
    }

    /// "right there", "500 feet away", "right at school", "0.2 miles from school".
    /// Distances are straight-line, not route distances.
    static func distance(_ meters: CLLocationDistance, from place: String? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        if meters < 75 {
            return place.map { "right at \($0)" } ?? "right there"
        }
        let formatted = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .wide, usage: .road).locale(locale))
        return place.map { "\(formatted) from \($0)" } ?? "\(formatted) away"
    }

    /// A rounded distance for settings and ride messages: "0.3 miles",
    /// "500 feet", "500 meters", "1.2 kilometers". `.abbreviated` gives
    /// "0.3 mi" or "500 m" for tight spots on screen.
    static func length(
        _ meters: CLLocationDistance,
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .wide,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let measurement: Measurement<UnitLength>
        if locale.measurementSystem == .us {
            let miles = meters / 1_609.344
            measurement = miles >= 0.1
                ? Measurement(value: (miles * 10).rounded() / 10, unit: .miles)
                : Measurement(value: (meters * 3.28084 / 50).rounded() * 50, unit: .feet)
        } else {
            measurement = meters >= 1_000
                ? Measurement(value: (meters / 100).rounded() / 10, unit: .kilometers)
                : Measurement(value: (meters / 50).rounded() * 50, unit: .meters)
        }
        return measurement.formatted(.measurement(width: width, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    /// Roughly how long riding a straight-line distance takes, on city
    /// streets at a typical speed: "about 3 minutes by bike".
    static func bikeTime(_ meters: CLLocationDistance) -> String {
        let minutes = meters * SavingsModel.streetFactor / SavingsModel.ridingSpeed / 60
        if minutes < 1 { return "under a minute by bike" }
        let rounded = Int(minutes.rounded())
        return rounded == 1 ? "about 1 minute by bike" : "about \(rounded) minutes by bike"
    }

    /// Thousands separators for large counts: "35,393".
    static func number(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.locale(locale))
    }

    static func ordinal(_ n: Int) -> String {
        let lastTwo = n % 100
        if (11...13).contains(lastTwo) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// Makes an Apple Maps instruction sound right when spoken: "Turn left
    /// onto W 4th St" → "Turn left onto West 4th Street", and "The
    /// destination is on your left" → "The dock is on your left".
    static func instruction(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            .replacingOccurrences(of: "&", with: " and ")
        if text.range(of: #"^Arrive\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "You'll reach the dock"
        }
        text = replace(#"\b([Tt])he destination\b"#, in: text) { groups in "\(groups[1])he dock" }
        text = replace(#"\bE\b(?=\s+\d)"#, in: text) { _ in "East" }
        text = replace(#"\bW\b(?=\s+\d)"#, in: text) { _ in "West" }
        text = replace(#"\bN\b(?=\s+\d)"#, in: text) { _ in "North" }
        text = replace(#"\bS\b(?=\s+\d)"#, in: text) { _ in "South" }
        text = replace(#"\b(\d+)\s+St\b"#, in: text) { groups in Int(groups[1]).map { "\(ordinal($0)) Street" } ?? groups[0] }
        text = replace(#"\b(\d+)\s+Ave\b"#, in: text) { groups in Int(groups[1]).map { "\(ordinal($0)) Avenue" } ?? groups[0] }
        // "St Marks Pl" is Saint Marks Place; "Bleecker St" is Bleecker Street.
        text = replace(#"\bSt\b\.?(?=\s+[A-Z][a-z])"#, in: text) { _ in "Saint" }
        let words = ["St": "Street", "Ave": "Avenue", "Pl": "Place", "Blvd": "Boulevard", "Rd": "Road",
                     "Dr": "Drive", "Pkwy": "Parkway", "Hwy": "Highway", "Sq": "Square", "Ln": "Lane"]
        for (short, long) in words {
            text = replace(#"\b\#(short)\b\.?"#, in: text) { _ in long }
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "Turn left" → "turn left", for the middle of a sentence.
    static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Ends a sentence with a period unless it already has punctuation.
    static func period(_ text: String) -> String {
        guard let last = text.last, !".!?".contains(last) else { return text }
        return text + "."
    }

    /// Uppercases the first letter so sentences that start with a
    /// lowercase place name ("school") still read as sentences on screen.
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Replaces every match of `pattern`, passing the full match and its
    /// capture groups (index 0 is the whole match) to `transform`.
    private static func replace(_ pattern: String, in text: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            result = result.replacingCharacters(in: match.range, with: transform(groups)) as NSString
        }
        return result as String
    }
}
