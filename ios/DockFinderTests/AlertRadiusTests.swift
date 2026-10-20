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
import MapKit
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

    @Test func movedPinsWithoutAnAddressAreSavedWithoutOne() {
        let school = SavedPlace(name: "School", latitude: 40.7290, longitude: -73.9965, address: "44 W 4th St")
        let pin = Destination(name: Destination.droppedPinName, latitude: 40.74, longitude: -73.99)
        let moved = school.relocated(to: pin, alertDistance: 500)
        #expect(moved.address == nil, "not \"Dropped Pin\", and not the old address either")
        #expect(moved.latitude == 40.74)
    }

    @Test func onlyRealAddressesOrPlaceNamesAreSaved() {
        func spot(_ name: String, address: String? = nil) -> Destination {
            Destination(name: name, latitude: 40.74, longitude: -73.99, address: address)
        }
        #expect(spot(Destination.droppedPinName).savedAddress == nil)
        #expect(spot(Destination.currentLocationName).savedAddress == nil)
        #expect(spot(Destination.droppedPinName, address: "60 Washington Sq S").savedAddress == "60 Washington Sq S")
        #expect(spot("NYU Stern").savedAddress == "NYU Stern", "a search result without an address keeps its name")
        #expect(spot("NYU Stern", address: "44 W 4th St").savedAddress == "44 W 4th St")
    }

    @Test(arguments: [
        (500.0, 1, 550.0),
        (500.0, -1, 450.0),
        (512.0, 1, 550.0),
        (150.0, -1, 150.0),
        (1_500.0, 1, 1_500.0),
        (1_480.0, 1, 1_500.0),
    ])
    func voiceOverStepsTheRadiusBy50Meters(from distance: Double, steps: Int, to stepped: Double) {
        #expect(SavedPlace.steppedAlertDistance(distance, by: steps) == stepped)
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

// MARK: - The map editor's camera

struct AlertMapGeometryTests {
    let stern = CLLocationCoordinate2D(latitude: 40.7291, longitude: -73.9965)

    @Test(arguments: [150.0, 500.0, 1_500.0])
    func theFramedRegionShowsTheWholeCircle(radius: Double) {
        let region = AlertMapGeometry.region(center: stern, radius: radius)
        #expect(AlertMapGeometry.circle(center: stern, radius: radius, fitsIn: region))
        #expect(!AlertMapGeometry.circle(center: stern, radius: radius * 1.5, fitsIn: region), "and isn't zoomed far out")
    }

    @Test func aCircleNudgedOffScreenNoLongerFits() {
        let region = AlertMapGeometry.region(center: stern, radius: 500)
        let moved = AlertMapGeometry.coordinate(stern, movedNorth: 300, east: 0)
        #expect(!AlertMapGeometry.circle(center: moved, radius: 500, fitsIn: region))
        let nudged = AlertMapGeometry.coordinate(stern, movedNorth: 25, east: -25)
        #expect(AlertMapGeometry.circle(center: nudged, radius: 500, fitsIn: region))
    }

    @Test func nudgesMoveAboutTheRightDistance() {
        let here = CLLocation(latitude: stern.latitude, longitude: stern.longitude)
        for (north, east) in [(25.0, 0.0), (0.0, 25.0), (-25.0, 0.0), (0.0, -25.0)] {
            let moved = AlertMapGeometry.coordinate(stern, movedNorth: north, east: east)
            let distance = here.distance(from: CLLocation(latitude: moved.latitude, longitude: moved.longitude))
            #expect(abs(distance - 25) < 0.5)
        }
    }

    @Test func tapsOnThePinAreNotTapsOnTheMap() {
        let tip = CGPoint(x: 200, y: 300)
        let area = AlertMapGeometry.pinHitArea(tip: tip)
        // The pin's head sits about 25 pt above its tip: the tap that used to walk it north.
        #expect(area.contains(CGPoint(x: 200, y: 275)))
        #expect(area.contains(CGPoint(x: 200, y: 300)), "its tip")
        #expect(area.contains(CGPoint(x: 225, y: 290)), "a near miss still counts")
        #expect(!area.contains(CGPoint(x: 200, y: 320)), "just below the tip is the map")
        #expect(!area.contains(CGPoint(x: 240, y: 290)))
        #expect(!area.contains(CGPoint(x: 200, y: 230)))
    }

    @Test func aDraggedPinKeepsItsGapFromTheFinger() {
        let tip = CGPoint(x: 200, y: 300)
        // Grabbed by its head, 25 pt above the tip, and moved 40 right and 10 down.
        let moved = AlertMapGeometry.draggedTip(tip, from: CGPoint(x: 202, y: 275), to: CGPoint(x: 242, y: 285))
        #expect(moved == CGPoint(x: 240, y: 310))
    }

    @Test func holdingThePinWithoutMovingIsNotADrag() {
        #expect(!AlertMapGeometry.isDrag(.zero))
        #expect(!AlertMapGeometry.isDrag(CGSize(width: 1, height: 2)))
        #expect(AlertMapGeometry.isDrag(CGSize(width: 3, height: 0)))
        #expect(AlertMapGeometry.isDrag(CGSize(width: -40, height: 12)))
    }

    @Test func onlyNearbyStationsAreShown() {
        let stations = [
            info("near", "Washington Pl & Greene St", 40.7299, -73.9955),
            info("edge", "W 13 St & 5 Ave", 40.7350, -73.9940),
            info("far", "Smith St & Bergen St", 40.6861, -73.9906),
        ]
        #expect(AlertMapGeometry.stations(stations, within: 1_200, of: stern).map(\.stationID) == ["near", "edge"])
        #expect(AlertMapGeometry.stations(stations, within: 300, of: stern).map(\.stationID) == ["near"])
    }
}

// MARK: - When the editor reframes the circle

struct AlertMapCameraTests {
    @Test func aPinMovedOffScreenIsReframedEvenRightAfterAPan() {
        #expect(AlertMapCamera.shouldReframe(after: .pinMoved, circleFits: false, riderMovedMapRecently: true))
        #expect(AlertMapCamera.shouldReframe(after: .pinMoved, circleFits: false, riderMovedMapRecently: false))
    }

    @Test func fineTuningThatStillFitsLeavesTheCameraAlone() {
        #expect(!AlertMapCamera.shouldReframe(after: .pinMoved, circleFits: true, riderMovedMapRecently: false))
        #expect(!AlertMapCamera.shouldReframe(after: .radiusChanging, circleFits: true, riderMovedMapRecently: false))
        #expect(AlertMapCamera.shouldReframe(after: .radiusChanging, circleFits: false, riderMovedMapRecently: true))
    }

    @Test func aNewPlaceIsFramedUnlessTheRiderIsAlreadyLookingAtIt() {
        #expect(AlertMapCamera.shouldReframe(after: .placeChanged, circleFits: true, riderMovedMapRecently: false))
        #expect(AlertMapCamera.shouldReframe(after: .placeChanged, circleFits: false, riderMovedMapRecently: true))
        #expect(!AlertMapCamera.shouldReframe(after: .placeChanged, circleFits: true, riderMovedMapRecently: true))
    }

    @Test func theFirstPinAndASettledRadiusAreAlwaysFramed() {
        for fits in [true, false] {
            for panned in [true, false] {
                #expect(AlertMapCamera.shouldReframe(after: .firstPin, circleFits: fits, riderMovedMapRecently: panned))
                #expect(AlertMapCamera.shouldReframe(after: .radiusSet, circleFits: fits, riderMovedMapRecently: panned))
            }
        }
    }
}

// MARK: - A moved pin's address lookup can't hold up Save

struct AddressLookupTimeoutTests {
    private struct SlowSearch: PlaceSearching {
        let delay: Duration
        let answer: String?
        func search(_ query: String) async throws -> [Destination] { [] }
        func address(for location: CLLocation) async -> String? {
            try? await Task.sleep(for: delay)
            return answer
        }
    }

    private let spot = CLLocation(latitude: 40.7291, longitude: -73.9965)

    @Test func aQuickLookupIsUsed() async {
        let search = SlowSearch(delay: .zero, answer: "44 W 4th St")
        #expect(await search.address(for: spot, timeout: .seconds(5)) == "44 W 4th St")
    }

    @Test func aLookupThatHangsGivesUpAtTheTimeout() async {
        let search = SlowSearch(delay: .seconds(30), answer: "44 W 4th St")
        let clock = ContinuousClock()
        let started = clock.now
        let address = await search.address(for: spot, timeout: .milliseconds(200))
        #expect(address == nil)
        #expect(clock.now - started < .seconds(5))
    }

    @Test func anOperationThatIgnoresCancellationDoesNotHoldItUp() async {
        let clock = ContinuousClock()
        let started = clock.now
        let value: Int? = await firstValue(within: .milliseconds(100)) {
            // Busy-waits rather than sleeping, so cancelling it does nothing.
            let end = ContinuousClock.now + .seconds(1)
            while ContinuousClock.now < end {}
            return 1
        }
        #expect(value == nil)
        #expect(clock.now - started < .milliseconds(800))
    }
}
