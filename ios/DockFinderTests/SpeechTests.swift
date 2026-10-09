//
//  SpeechTests.swift
//  DockFinderTests
//

import Foundation
import Testing
@testable import DockFinder

struct SpeechTests {
    @Test(arguments: [
        ("W 15 St & 6 Ave", "West 15th and 6th"),
        ("Mercer St & Bleecker St", "Mercer and Bleecker"),
        ("E 17 St & Broadway", "East 17th and Broadway"),
        ("Washington Pl & Greene St", "Washington and Greene"),
        ("1 Ave & E 18 St", "1st and East 18th"),
        ("W 22 St & 10 Ave", "West 22nd and 10th"),
        ("Pier 40 - Hudson River Park", "Pier 40 - Hudson River Park"),
    ])
    func stationNamesReadNaturally(name: String, spoken: String) {
        #expect(Speech.stationName(name) == spoken)
    }

    @Test func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 103, 111].map(Speech.ordinal)
            == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "103rd", "111th"])
    }

    @Test func veryCloseDistancesAreRightThere() {
        #expect(Speech.distance(40) == "right there")
        #expect(Speech.distance(40, from: "school") == "right at school")
    }

    @Test func distancesUseTheLocalesUnits() {
        let us = Speech.distance(400, locale: Locale(identifier: "en_US"))
        #expect(us.hasSuffix(" away"))
        #expect(us.contains("feet") || us.contains("mile"))

        let uk = Speech.distance(400, from: "work", locale: Locale(identifier: "en_DE"))
        #expect(uk.hasSuffix(" from work"))
        #expect(uk.contains("met"))
    }

    @Test func countsAndNumbers() {
        #expect(Speech.docksOpen(1) == "1 dock open")
        #expect(Speech.docksOpen(5) == "5 docks open")
        #expect(Speech.bikes(1) == "1 bike")
        #expect(Speech.number(35_393, locale: Locale(identifier: "en_US")) == "35,393")
    }
}

struct StationNameMatcherTests {
    let names = [
        "Mercer St & Bleecker St",
        "W 15 St & 6 Ave",
        "W 16 St & 6 Ave",
        "E 17 St & Broadway",
        "Washington Pl & Greene St",
    ]

    private func best(_ query: String) -> String? {
        names
            .map { ($0, StationNameMatcher.score(name: $0, query: query)) }
            .filter { $0.1 >= StationNameMatcher.threshold }
            .max { $0.1 < $1.1 }?.0
    }

    @Test func matchesHowRidersSayStations() {
        #expect(best("Mercer and Bleecker") == "Mercer St & Bleecker St")
        #expect(best("west 15th and 6th") == "W 15 St & 6 Ave")
        #expect(best("West Sixteenth and Sixth Avenue") == "W 16 St & 6 Ave")
        #expect(best("east 17th street and broadway") == "E 17 St & Broadway")
    }

    @Test func toleratesOneTypo() {
        #expect(best("Mercer and Bleeker") == "Mercer St & Bleecker St")
    }

    @Test func numbersMustMatch() {
        #expect(best("west 25th and 6th") == nil)
    }

    @Test func unrelatedNamesDontMatch() {
        #expect(best("Times Square") == nil)
        #expect(best("") == nil)
    }
}
