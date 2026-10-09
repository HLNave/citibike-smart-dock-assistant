//
//  RideAndPlaceTests.swift
//  DockFinderTests
//
//  Rides ("start a ride to school"), backup docks, and saved-place
//  storage, matching and validation.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

// MARK: - Ride rules

struct RideTests {
    let school = Destination(name: "school", latitude: 40.7290, longitude: -73.9965)

    @Test func arrivesInsideTheAlertDistance() {
        let ride = Ride(destination: school, alertDistance: 500, startedAt: referenceNow)
        let farAway = CLLocation(latitude: 40.7400, longitude: -73.9965)   // ≈ 1.2 km north
        let close = CLLocation(latitude: 40.7320, longitude: -73.9965)     // ≈ 330 m north

        guard case .riding(let distance?) = ride.progress(at: farAway, now: referenceNow) else {
            Issue.record("expected to still be riding")
            return
        }
        #expect(distance > 1_000)
        #expect(ride.progress(at: close, now: referenceNow) == .arrived)
        #expect(ride.progress(at: nil, now: referenceNow) == .riding(nil))
    }

    @Test func expiresAfterAnHour() {
        let ride = Ride(destination: school, startedAt: referenceNow)
        let close = CLLocation(latitude: 40.7291, longitude: -73.9965)
        #expect(!ride.hasExpired(now: referenceNow.addingTimeInterval(59 * 60)))
        #expect(ride.progress(at: close, now: referenceNow.addingTimeInterval(61 * 60)) == .expired)
    }

    @Test func survivesAppRelaunch() throws {
        let ride = Ride(destination: school, savedPlaceID: UUID(), alertDistance: 800, startedAt: referenceNow)
        let decoded = try JSONDecoder().decode(Ride.self, from: JSONEncoder().encode(ride))
        #expect(decoded == ride)
    }
}

// MARK: - Parsing

struct RideParsingTests {
    @Test(arguments: [
        ("start a ride to school", ParsedRequest.startRide("school")),
        ("Start my ride to Union Square.", .startRide("union square")),
        ("begin a trip to 44 west 4th street", .startRide("44 west 4th street")),
        ("I'm riding to work", .startRide("work")),
        ("im heading to nyu stern", .startRide("nyu stern")),
        ("ride to the met", .startRide("the met")),
        ("start a ride", .startRide("")),
        ("end my ride", .endRide),
        ("cancel ride", .endRide),
        ("I'm done riding", .endRide),
    ])
    func rides(request: String, expected: ParsedRequest) {
        #expect(KeywordRequestParser.parse(request) == expected)
    }

    @Test(arguments: [
        ("my school dock is Mercer and Bleecker", ParsedRequest.setUsualDock(place: "school", station: "mercer and bleecker")),
        ("set my work dock to west 15th and 6th", .setUsualDock(place: "work", station: "west 15th and 6th")),
        ("use court and state as my gym dock", .setUsualDock(place: "gym", station: "court and state")),
        ("my school dock is full", .station("my school dock")),
        ("save this spot as gym", .savePlace("gym")),
        ("remember my location as Mom's", .savePlace("mom's")),
    ])
    func placeEdits(request: String, expected: ParsedRequest) {
        #expect(KeywordRequestParser.parse(request) == expected)
    }
}

// MARK: - Router: rides and voice edits

@MainActor
struct RideRouterTests {
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)
    /// ≈ 3 km from both stations.
    let farFromEverything = CLLocation(latitude: 40.7130, longitude: -73.9900)

    private func router(
        store: SavedPlacesStore,
        rides: RideSpy,
        places: StubPlaces = StubPlaces(),
        here: CLLocation? = nil
    ) -> AssistantRouter {
        let fix = LocationFix(location: here ?? farFromEverything, isApproximate: false)
        return AssistantRouter(
            service: DockFinderService(
                location: StubLocation(result: .success(fix)),
                feeds: StubFeeds(
                    information: .success(informationFeed([near, mid])),
                    status: .success(statusFeed([status("near", docks: 0), status("mid", docks: 6)]))
                ),
                now: { referenceNow }
            ),
            placeSearch: places,
            store: store,
            rides: rides,
            parsers: [KeywordRequestParser()],
            backend: nil,
            location: StubLocation(result: .success(fix)),
            sessionID: "app-test"
        )
    }

    @Test func rideToASavedPlaceUsesItsAlertDistance() async throws {
        let school = SavedPlace(name: "School", latitude: 40.6861, longitude: -73.9906, alertDistance: 800)
        let rides = RideSpy()
        let answer = try await router(store: testStore([school]), rides: rides).answer("start a ride to my school")

        let ride = try #require(rides.started.first)
        #expect(ride.savedPlaceID == school.id)
        #expect(ride.alertDistance == 800)
        #expect(answer.text.hasPrefix("Got it. I'll tell you where to dock when you're about "))
        #expect(answer.text.hasSuffix(" from School."))
    }

    @Test func rideToAnyPlaceUsesTheMap() async throws {
        let rides = RideSpy()
        let places = StubPlaces(results: ["union square": Destination(name: "Union Square Park", latitude: 40.7359, longitude: -73.9911)])
        _ = try await router(store: testStore(), rides: rides, places: places).answer("start a ride to union square")

        let ride = try #require(rides.started.first)
        #expect(ride.destination.name == "union square")
        #expect(ride.savedPlaceID == nil)
        #expect(ride.alertDistance == SavedPlace.defaultAlertDistance)
    }

    @Test func startingAlreadyNearbyAnswersRightAway() async throws {
        let school = SavedPlace(name: "School", latitude: 40.6861, longitude: -73.9906, usualStationID: "near")
        let rides = RideSpy()
        let answer = try await router(store: testStore([school]), rides: rides, here: CLLocation(latitude: 40.6865, longitude: -73.9906))
            .answer("start a ride to school")
        #expect(rides.started.isEmpty)
        #expect(answer.text.hasPrefix("Your usual dock is full. Go to Court and State"))
    }

    @Test func withoutAlwaysLocationTheRiderIsTold() async throws {
        let school = SavedPlace(name: "School", latitude: 40.6861, longitude: -73.9906)
        let answer = try await router(store: testStore([school]), rides: RideSpy(canTrackInBackground: false))
            .answer("start a ride to school")
        #expect(answer.text.contains("allow location access all the time"))
    }

    @Test func rideWithoutDestinationAsksForOne() async throws {
        let rides = RideSpy()
        let answer = try await router(store: testStore(), rides: rides).answer("start a ride")
        #expect(rides.started.isEmpty)
        #expect(answer.text.hasPrefix("Where are you riding to?"))
    }

    @Test func endingARide() async throws {
        let rides = RideSpy(currentRide: Ride(destination: Destination(name: "school", latitude: 0, longitude: 0)))
        let answer = try await router(store: testStore(), rides: rides).answer("end my ride")
        #expect(rides.endCount == 1)
        #expect(answer.text == "Okay, I stopped watching your ride to school.")

        let nothing = try await router(store: testStore(), rides: RideSpy()).answer("end my ride")
        #expect(nothing.text == "You don't have a ride in progress.")
    }

    @Test func settingAUsualDockByVoice() async throws {
        let school = SavedPlace(name: "School", latitude: 40.6861, longitude: -73.9906)
        let store = testStore([school])
        let answer = try await router(store: store, rides: RideSpy()).answer("my school dock is court and state")
        #expect(answer.text == "Got it. Court and State is your school dock.")
        #expect(store.places.first?.usualStationID == "mid")
        #expect(store.places.first?.usualStationName == "Court St & State St")
    }

    @Test func settingADockForAnUnknownPlace() async throws {
        let answer = try await router(store: testStore(), rides: RideSpy()).answer("my gym dock is court and state")
        #expect(answer.text.hasPrefix("You don't have a saved place called gym."))
    }

    @Test func savingWhereYouAreByVoice() async throws {
        let store = testStore()
        let answer = try await router(store: store, rides: RideSpy()).answer("save this spot as gym")
        #expect(answer.text == "Saved this spot as gym. Next time, say start a ride to gym.")
        #expect(store.places.first?.name == "Gym")
        #expect(store.places.first?.latitude == farFromEverything.coordinate.latitude)

        let duplicate = try await router(store: store, rides: RideSpy()).answer("save this spot as gym")
        #expect(duplicate.text.contains("already used"))
        #expect(store.places.count == 1)
    }
}

// MARK: - Backup docks

struct BackupDockTests {
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)
    let other = info("other", "Hoyt St & Warren St", 40.6866, -73.9890)
    let school = Destination(name: "school", latitude: 40.6862, longitude: -73.9906)

    private func network(_ statuses: [StationStatus]) throws -> StationNetwork {
        try StationNetwork(information: informationFeed([near, mid, other]), status: statusFeed(statuses), now: referenceNow)
    }

    @Test func backupIsTriedBeforeTheNearestStation() throws {
        // `other` is closer than `mid`, but `mid` is the backup.
        let result = DockFinderService.dock(
            near: school, usualStationID: "near", backupStationID: "mid",
            in: try network([status("near", docks: 0), status("mid", docks: 8), status("other", docks: 20)])
        )
        #expect(result.selectedIsBackup)
        #expect(result.selected?.id == "mid")
        #expect(result.summary.hasPrefix("Your usual dock is full. Your backup, Court and State, has 8 docks open, "))
    }

    @Test func fullBackupFallsThroughToTheNearestStation() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "near", backupStationID: "mid",
            in: try network([status("near", docks: 0), status("mid", docks: 1), status("other", docks: 20)])
        )
        #expect(!result.selectedIsBackup)
        #expect(result.selected?.id == "other")
    }

    @Test func usualDockStillComesFirst() throws {
        let result = DockFinderService.dock(
            near: school, usualStationID: "near", backupStationID: "mid",
            in: try network([status("near", docks: 5), status("mid", docks: 8)])
        )
        #expect(result.usesUsualDock)
        #expect(result.summary == "Your usual dock has 5 docks open.")
    }
}

// MARK: - Saved places

@MainActor
struct SavedPlaceRobustnessTests {
    @Test func placesFromTheFirstVersionStillLoad() throws {
        // Saved before aliases, backup docks and alert distances existed.
        let legacy = #"[{"id":"9C6D1D2B-6E2C-4C5B-9C1C-2D5F0F3E7A11","name":"School","latitude":40.729,"longitude":-73.996,"usualStationID":"near","usualStationName":"Smith St & Bergen St"}]"#
        let defaults = UserDefaults(suiteName: "legacy-\(UUID())")!
        defaults.set(Data(legacy.utf8), forKey: SavedPlacesStore.storageKey)

        let place = try #require(SavedPlacesStore(defaults: defaults, onChange: {}).places.first)
        #expect(place.name == "School")
        #expect(place.usualStationID == "near")
        #expect(place.aliases.isEmpty)
        #expect(place.backupStationID == nil)
        #expect(place.alertDistance == SavedPlace.defaultAlertDistance)
    }

    @Test func oneDamagedPlaceDoesntLoseTheRest() {
        let mixed = #"[{"name":"School","latitude":40.7,"longitude":-73.9},{"name":"Broken"},{"name":"Work","latitude":40.75,"longitude":-73.98}]"#
        let defaults = UserDefaults(suiteName: "mixed-\(UUID())")!
        defaults.set(Data(mixed.utf8), forKey: SavedPlacesStore.storageKey)
        #expect(SavedPlacesStore(defaults: defaults, onChange: {}).places.map(\.name) == ["School", "Work"])
    }

    @Test func unreadableDataIsKeptAside() {
        let defaults = UserDefaults(suiteName: "corrupt-\(UUID())")!
        defaults.set(Data("not json".utf8), forKey: SavedPlacesStore.storageKey)
        #expect(SavedPlacesStore(defaults: defaults, onChange: {}).places.isEmpty)
        #expect(defaults.data(forKey: SavedPlacesStore.unreadableBackupKey) == Data("not json".utf8))
    }

    @Test(arguments: ["school", "School", "my school", "the school", "my school dock", "Stern", "my stern dock", "scool"])
    func matchesHowRidersRefer(spoken: String) {
        let school = SavedPlace(name: "School", aliases: ["Stern"], latitude: 0, longitude: 0)
        #expect(school.matches(spoken))
    }

    @Test(arguments: ["work", "", "dock", "schools district"])
    func doesntMatchOtherWords(spoken: String) {
        let school = SavedPlace(name: "School", aliases: ["Stern"], latitude: 0, longitude: 0)
        #expect(!school.matches(spoken))
    }

    @Test func exactNamesBeatTypoMatches() {
        let store = testStore([
            SavedPlace(name: "Home", latitude: 0, longitude: 0),
            SavedPlace(name: "Homer", latitude: 1, longitude: 1),
        ])
        #expect(store.place(matching: "homer")?.name == "Homer")
        #expect(store.place(matching: "my home")?.name == "Home")
    }

    @Test func namesAndAliasesMustBeUnique() {
        let store = testStore([SavedPlace(name: "School", aliases: ["Stern"], latitude: 0, longitude: 0)])
        #expect(store.validate(name: "  ") == .emptyName)
        #expect(store.validate(name: "my school") == .nameTaken(name: "my school", place: "School"))
        #expect(store.validate(name: "Work", aliases: ["stern"]) == .nameTaken(name: "stern", place: "School"))
        #expect(store.validate(name: "Work", aliases: ["Office"]) == nil)
        let school = store.places[0]
        #expect(store.validate(name: "School", aliases: ["Stern"], excluding: school.id) == nil, "a place doesn't clash with itself")
    }

    @Test func aliasesAreCleanedUp() {
        let store = testStore([SavedPlace(name: " School ", aliases: ["Stern", " stern", "", "School", "Class"], latitude: 0, longitude: 0)])
        #expect(store.places[0].name == "School")
        #expect(store.places[0].aliases == ["Stern", "Class"])
    }

    @Test func usualAndBackupDocksStayDifferent() {
        let store = testStore([SavedPlace(name: "School", latitude: 0, longitude: 0)])
        let id = store.places[0].id
        store.setUsualDock(stationID: "a", stationName: "A", for: id)
        store.setBackupDock(stationID: "a", stationName: "A", for: id)
        #expect(store.places[0].backupStationID == nil, "the usual dock can't also be the backup")

        store.setBackupDock(stationID: "b", stationName: "B", for: id)
        store.setUsualDock(stationID: "b", stationName: "B", for: id)
        #expect(store.places[0].usualStationID == "b")
        #expect(store.places[0].backupStationID == nil, "promoting the backup clears it")
    }

    @Test func reordering() {
        let store = testStore(["A", "B", "C"].map { SavedPlace(name: $0, latitude: 0, longitude: 0) })
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.places.map(\.name) == ["C", "A", "B"])
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.places.map(\.name) == ["A", "B", "C"])
    }
}
