//
//  AlertRadiusTests.swift
//  DockFinderTests
//
//  A saved place's alert radius, picked on a map: any value in range,
//  snapped to round steps, kept in range on load and save, and a moved or
//  resized place gets a new geofence.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

@MainActor
struct AlertRadiusTests {
    @Test(arguments: [
        (512.0, 500.0),
        (525.0, 550.0),
        (0.0, 150.0),
        (149.0, 150.0),
        (1_480.0, 1_500.0),
        (9_000.0, 1_500.0),
        (-Double.infinity, 150.0),
        (Double.nan, SavedPlace.defaultAlertDistance),
    ])
    func sliderPositionsSnapToSteps(position: Double, snapped: Double) {
        #expect(SavedPlace.snappedAlertDistance(position) == snapped)
    }

    @Test(arguments: [
        (300.0, 300.0),
        (640.0, 640.0),
        (90.0, 150.0),
        (5_000.0, 1_500.0),
        (0.0, SavedPlace.defaultAlertDistance),
        (-200.0, SavedPlace.defaultAlertDistance),
        (Double.infinity, SavedPlace.defaultAlertDistance),
    ])
    func outOfRangeRadiiAreClamped(distance: Double, clamped: Double) {
        #expect(SavedPlace.clampedAlertDistance(distance) == clamped)
    }

    @Test func theDefaultIsInRange() {
        #expect(SavedPlace.alertDistanceRange.contains(SavedPlace.defaultAlertDistance))
        #expect(SavedPlace.snappedAlertDistance(SavedPlace.defaultAlertDistance) == SavedPlace.defaultAlertDistance)
    }

    private func loaded(alertDistance: Double) throws -> SavedPlace {
        let json = #"[{"name":"School","latitude":40.729,"longitude":-73.996,"alertDistance":\#(alertDistance)}]"#
        let defaults = UserDefaults(suiteName: "radius-\(UUID())")!
        defaults.set(Data(json.utf8), forKey: SavedPlacesStore.storageKey)
        return try #require(SavedPlacesStore(defaults: defaults, onChange: {}).places.first)
    }

    @Test(arguments: [300.0, 500.0, 800.0, 1_200.0])
    func placesSavedWithTheOldPresetsKeepTheirRadius(preset: Double) throws {
        #expect(try loaded(alertDistance: preset).alertDistance == preset)
    }

    @Test func outOfRangeSavedRadiiAreClampedOnLoad() throws {
        #expect(try loaded(alertDistance: 40).alertDistance == 150)
        #expect(try loaded(alertDistance: 20_000).alertDistance == 1_500)
        #expect(try loaded(alertDistance: 0).alertDistance == SavedPlace.defaultAlertDistance)
    }

    @Test func savingClampsTheRadius() {
        let store = testStore([SavedPlace(name: "School", latitude: 40.7, longitude: -73.9, alertDistance: 20)])
        #expect(store.places[0].alertDistance == 150)
        var place = store.places[0]
        place.alertDistance = 9_000
        store.update(place)
        #expect(store.places[0].alertDistance == 1_500)
    }

    @Test func movingOrResizingAPlaceIsSavedAndResyncsGeofences() throws {
        let defaults = UserDefaults(suiteName: "move-\(UUID())")!
        var changes = 0
        let store = SavedPlacesStore(defaults: defaults, onChange: { changes += 1 })
        store.add(SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, address: "44 W 4th St"))
        let added = changes

        let moved = store.places[0].relocated(
            to: Destination(name: "Dropped Pin", latitude: 40.7301, longitude: -73.9950, address: "60 Washington Sq S"),
            alertDistance: 650
        )
        store.update(moved)

        // onChange is what re-syncs PlaceArrivalMonitor's geofences (see SavedPlacesStore.shared).
        #expect(changes == added + 1)
        let reloaded = try #require(SavedPlacesStore.load(from: defaults).first)
        #expect(reloaded.latitude == 40.7301)
        #expect(reloaded.longitude == -73.9950)
        #expect(reloaded.address == "60 Washington Sq S")
        #expect(reloaded.alertDistance == 650)
    }

    @Test func savingWithoutMovingThePinKeepsTheAddress() {
        let school = SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, address: "44 W 4th St", usualStationID: "near")
        let resized = school.relocated(to: Destination(name: "NYU Stern", latitude: 40.7290, longitude: -73.9965), alertDistance: 300)
        #expect(resized.address == "44 W 4th St")
        #expect(resized.alertDistance == 300)
        #expect(resized.usualStationID == "near")
    }

    @Test func movedPinsWithoutAnAddressUseTheirName() {
        let school = SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, address: "44 W 4th St")
        let moved = school.relocated(to: Destination(name: "Dropped Pin", latitude: 40.74, longitude: -73.99), alertDistance: 500)
        #expect(moved.address == "Dropped Pin")
    }

    @Test func geofencesAreReplacedWhenThePlaceMovesOrResizes() {
        let school = SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, alertDistance: 500)
        let center = CLLocationCoordinate2D(latitude: 40.7290, longitude: -73.9965)
        #expect(PlaceArrivalRules.geofenceIsCurrent(center: center, radius: 500, for: school))
        #expect(!PlaceArrivalRules.geofenceIsCurrent(center: center, radius: 650, for: school), "new radius")
        #expect(!PlaceArrivalRules.geofenceIsCurrent(center: .init(latitude: 40.7301, longitude: -73.9965), radius: 500, for: school), "moved")
    }

    @Test func docksLeftFarBehindByAMoveAreReported() {
        let near = info("near", "Mercer St & Bleecker St", 40.7290, -73.9965)
        let far = info("far", "Smith St & Bergen St", 40.6861, -73.9906)
        let school = SavedPlace(
            name: "School", latitude: 40.7290, longitude: -73.9965,
            usualStationID: "far", usualStationName: "Smith St & Bergen St",
            backupStationID: "near", backupStationName: "Mercer St & Bleecker St"
        )
        #expect(school.distantDocks(from: school.location, in: [near, far]).map(\.name) == ["Smith St & Bergen St"])
        let brooklyn = CLLocation(latitude: 40.6861, longitude: -73.9906)
        #expect(school.distantDocks(from: brooklyn, in: [near, far]).map(\.name) == ["Mercer St & Bleecker St"])
        #expect(school.distantDocks(from: school.location, in: []).isEmpty, "unknown stations aren't guessed at")
    }

    @Test func radiusLabelsUseTheLocalesUnits() {
        let us = Locale(identifier: "en_US")
        let metric = Locale(identifier: "en_GB")
        #expect(Speech.length(500, width: .abbreviated, locale: us) == "0.3 mi")
        #expect(Speech.length(150, width: .abbreviated, locale: us) == "500 ft")
        #expect(Speech.length(650, width: .abbreviated, locale: us) == "0.4 mi")
        #expect(Speech.length(500, width: .abbreviated, locale: metric) == "500 m")
        #expect(Speech.length(1_500, width: .abbreviated, locale: metric) == "1.5 km")
        #expect(Speech.length(650, locale: metric) == "650 metres", "VoiceOver reads the wide form")
    }

    @Test func bikeTimes() {
        #expect(Speech.bikeTime(150) == "under a minute by bike")
        #expect(Speech.bikeTime(200) == "about 1 minute by bike")
        #expect(Speech.bikeTime(300) == "about 2 minutes by bike")
        #expect(Speech.bikeTime(500) == "about 3 minutes by bike")
        #expect(Speech.bikeTime(1_500) == "about 8 minutes by bike")
    }
}
