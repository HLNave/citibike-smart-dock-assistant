//
//  TestSupport.swift
//  DockFinderTests
//

import CoreLocation
import Foundation
@testable import DockFinder

let referenceNow = Date(timeIntervalSince1970: 1_791_498_400)

/// Smith St & Bergen St, Brooklyn — the user's position in most tests.
let userLocation = CLLocation(latitude: 40.6861, longitude: -73.9906)

func info(_ id: String, _ name: String, _ lat: Double, _ lon: Double) -> StationInformation {
    StationInformation(stationID: id, name: name, latitude: lat, longitude: lon)
}

func status(
    _ id: String,
    docks: Int,
    bikes: Int = 0,
    ebikes: Int = 0,
    installed: Bool = true,
    returning: Bool = true,
    reported: Date? = referenceNow.addingTimeInterval(-30)
) -> StationStatus {
    StationStatus(
        stationID: id, numDocksAvailable: docks, numBikesAvailable: bikes, numEbikesAvailable: ebikes,
        isInstalled: installed, isReturning: returning, lastReported: reported
    )
}

func informationFeed(_ stations: [StationInformation], updated: Date = referenceNow) -> GBFSFeed<StationInformationPayload> {
    GBFSFeed(lastUpdated: updated, ttl: 60, data: StationInformationPayload(stations: stations))
}

func statusFeed(_ stations: [StationStatus], updated: Date = referenceNow) -> GBFSFeed<StationStatusPayload> {
    GBFSFeed(lastUpdated: updated, ttl: 60, data: StationStatusPayload(stations: stations))
}

struct StubFeeds: CitiBikeFeedProviding {
    var information: Result<GBFSFeed<StationInformationPayload>, DockFinderError>
    var status: Result<GBFSFeed<StationStatusPayload>, DockFinderError>

    func fetchStationInformation() async throws -> GBFSFeed<StationInformationPayload> {
        try information.get()
    }

    func fetchStationStatus() async throws -> GBFSFeed<StationStatusPayload> {
        try status.get()
    }
}

struct StubLocation: LocationProviding {
    var result: Result<LocationFix, DockFinderError>

    func currentLocation() async throws -> LocationFix {
        try result.get()
    }
}

/// A saved-places store backed by throwaway defaults.
@MainActor
func testStore(_ places: [SavedPlace] = []) -> SavedPlacesStore {
    let store = SavedPlacesStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!, onChange: {})
    places.forEach(store.add)
    return store
}

@MainActor
final class RideSpy: RideControlling {
    var currentRide: Ride?
    var canTrackInBackground: Bool
    private(set) var started: [Ride] = []
    private(set) var endCount = 0

    init(currentRide: Ride? = nil, canTrackInBackground: Bool = true) {
        self.currentRide = currentRide
        self.canTrackInBackground = canTrackInBackground
    }

    func start(_ ride: Ride) async {
        started.append(ride)
        currentRide = ride
    }

    func end() async {
        endCount += 1
        currentRide = nil
    }

    func setGuidesToDock(_ guides: Bool) {
        currentRide?.guidesToDock = guides
    }
}

@MainActor
final class GuidanceSpy: GuidanceControlling {
    var isActive: Bool
    var station: DockStation?
    var offered: DockStation?
    /// Thrown by `start`, when set.
    var startError: DockFinderError?
    private(set) var started: [DockStation] = []
    private(set) var siriLines: [String?] = []
    private(set) var stopCount = 0
    /// What was said in the directions voice.
    private(set) var said: [String] = []

    init(isActive: Bool = false, offered: DockStation? = nil, guidingTo station: DockStation? = nil) {
        self.isActive = isActive || station != nil
        self.offered = offered
        self.station = station
    }

    func offer(_ station: DockStation, now: Date) { offered = station }

    func recentOffer(now: Date) -> DockStation? { offered }

    func start(to station: DockStation, siriWillSay siriLine: String?) async throws -> String {
        if let startError { throw startError }
        started.append(station)
        siriLines.append(siriLine)
        isActive = true
        self.station = station
        return "Head to \(station.spokenName)."
    }

    func siriConfirmation(for station: DockStation) -> String {
        "Okay, directing you to \(station.spokenName)."
    }

    func stop() async {
        stopCount += 1
        isActive = false
        station = nil
    }

    func say(_ text: String) async {
        said.append(text)
    }
}

/// A router over two Brooklyn stations: Smith & Bergen ("near", full) and
/// Court & State ("mid", 6 docks), with the rider at Smith & Bergen.
@MainActor
func testRouter(
    parsers: [any RequestParsing] = [KeywordRequestParser()],
    places: any PlaceSearching = StubPlaces(),
    saved: [SavedPlace] = [],
    rides: RideSpy? = nil,
    backend: (any AssistantBackend)? = nil,
    moreStations: [(info: StationInformation, status: StationStatus)] = []
) -> AssistantRouter {
    let fix = LocationFix(location: userLocation, isApproximate: false)
    return AssistantRouter(
        service: DockFinderService(
            location: StubLocation(result: .success(fix)),
            feeds: StubFeeds(
                information: .success(informationFeed([
                    info("near", "Smith St & Bergen St", 40.6861, -73.9906),
                    info("mid", "Court St & State St", 40.6900, -73.9920),
                ] + moreStations.map(\.info))),
                status: .success(statusFeed([status("near", docks: 0, bikes: 3), status("mid", docks: 6, bikes: 2)] + moreStations.map(\.status)))
            ),
            now: { referenceNow }
        ),
        placeSearch: places,
        store: testStore(saved),
        rides: rides ?? RideSpy(),
        parsers: parsers,
        backend: backend,
        location: StubLocation(result: .success(fix)),
        sessionID: "app-test"
    )
}

struct StubBackend: AssistantBackend {
    var reply: String

    func ask(_ text: String, location: CLLocation?, sessionID: String) async throws -> String {
        reply
    }
}

/// A throwaway UserDefaults suite, deleted when the test that made it ends.
final class TemporaryDefaults {
    let name = "test-\(UUID())"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

@MainActor
final class SpeakerSpy: AnswerSpeaking {
    private(set) var spoken: [String] = []
    private(set) var notificationIDs: [String] = []

    func speakAnswer(_ text: String, title: String, notificationID: String) async {
        spoken.append(text)
        notificationIDs.append(notificationID)
    }
}
