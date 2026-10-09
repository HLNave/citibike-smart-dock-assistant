//
//  AssistantTests.swift
//  DockFinderTests
//
//  Free-form requests: what's understood on device, and when the n8n
//  backend is (and isn't) asked.
//

import CoreLocation
import Foundation
import Testing
@testable import DockFinder

struct KeywordRequestParserTests {
    @Test(arguments: [
        ("Find me a dock near Union Square", ParsedRequest.place("union square")),
        ("find somewhere to dock near NYU Stern please", .place("nyu stern")),
        ("Is there a dock by 44 West 4th Street?", .place("44 west 4th street")),
        ("find a dock near school", .place("school")),
        ("Find me a dock near me", .nearMe),
        ("where's the nearest dock", .nearMe),
        ("find me a dock", .nearMe),
        ("Is Mercer and Bleecker full?", .station("mercer and bleecker")),
        ("check my school dock", .station("my school dock")),
        ("does Court and State have room", .station("court and state")),
        ("how many docks are open at West 15th and 6th", .station("west 15th and 6th")),
        ("How many bikes are out?", .citywide),
        ("citywide status", .citywide),
    ])
    func understands(request: String, expected: ParsedRequest) {
        #expect(KeywordRequestParser.parse(request) == expected)
    }

    @Test(arguments: ["what's the weather", "tell me a joke", ""])
    func leavesOtherRequestsAlone(request: String) {
        #expect(KeywordRequestParser.parse(request) == nil)
    }
}

// MARK: - Router

private actor BackendSpy: AssistantBackend {
    var reply: Result<String, DockFinderError>
    private(set) var questions: [(text: String, location: CLLocation?, sessionID: String)] = []

    init(reply: Result<String, DockFinderError>) {
        self.reply = reply
    }

    func ask(_ text: String, location: CLLocation?, sessionID: String) async throws -> String {
        questions.append((text, location, sessionID))
        return try reply.get()
    }
}

private struct StubPlaces: PlaceSearching {
    var results: [String: Destination] = [:]

    func search(_ query: String) async throws -> [Destination] {
        guard let match = results[query] else { throw DockFinderError.placeNotFound(query) }
        return [match]
    }
}

private struct StubParser: RequestParsing {
    var result: ParsedRequest?
    var answerSource: DockAnswer.Source { .onDeviceModel }
    func parse(_ text: String) async -> ParsedRequest? { result }
}

@MainActor
struct AssistantRouterTests {
    let near = info("near", "Smith St & Bergen St", 40.6861, -73.9906)
    let mid = info("mid", "Court St & State St", 40.6900, -73.9920)

    private func router(
        parsers: [any RequestParsing] = [KeywordRequestParser()],
        places: StubPlaces = StubPlaces(),
        saved: [SavedPlace] = [],
        backend: BackendSpy? = nil
    ) -> AssistantRouter {
        AssistantRouter(
            service: DockFinderService(
                location: StubLocation(result: .success(LocationFix(location: userLocation, isApproximate: false))),
                feeds: StubFeeds(
                    information: .success(informationFeed([near, mid])),
                    status: .success(statusFeed([status("near", docks: 0, bikes: 3), status("mid", docks: 6, bikes: 2)]))
                ),
                now: { referenceNow }
            ),
            placeSearch: places,
            savedPlaces: saved,
            parsers: parsers,
            backend: backend,
            location: StubLocation(result: .success(LocationFix(location: userLocation, isApproximate: false))),
            sessionID: "app-test"
        )
    }

    @Test func understoodRequestsNeverReachTheBackend() async throws {
        let backend = BackendSpy(reply: .success("from the server"))
        let answer = try await router(backend: backend).answer("is court and state full?")
        #expect(answer.text == "Court and State has 6 docks open and 2 bikes.")
        #expect(answer.source == .onDevice)
        #expect(await backend.questions.isEmpty)
    }

    @Test func placesAreSearchedOnDeviceAndSpokenInTheRidersWords() async throws {
        let places = StubPlaces(results: ["union square": Destination(name: "Union Square Park", latitude: 40.6900, longitude: -73.9921)])
        let answer = try await router(places: places).answer("find me a dock near union square")
        #expect(answer.text == "Court and State has 6 docks open, right at union square.")
        #expect(answer.station?.id == "mid")
    }

    @Test func savedPlacesUseTheirUsualDock() async throws {
        let school = SavedPlace(name: "School", latitude: 40.6861, longitude: -73.9906, usualStationID: "near", usualStationName: "Smith St & Bergen St")
        let answer = try await router(saved: [school]).answer("find a dock near school")
        #expect(answer.text.hasPrefix("Your usual dock is full. Go to Court and State, 6 docks, "))
    }

    @Test func myPlaceDockChecksTheUsualStation() async throws {
        let school = SavedPlace(name: "School", latitude: 0, longitude: 0, usualStationID: "mid", usualStationName: "Court St & State St")
        let answer = try await router(saved: [school]).answer("check my school dock")
        #expect(answer.text == "Court and State has 6 docks open and 2 bikes.")
    }

    @Test func onDeviceModelHandlesOtherWording() async throws {
        let answer = try await router(parsers: [KeywordRequestParser(), StubParser(result: .citywide)])
            .answer("what's the situation with bikes across nyc")
        #expect(answer.text.hasSuffix("citywide. 1 station is full."))
        #expect(answer.source == .onDeviceModel)
    }

    @Test func unknownRequestsGoToTheBackend() async throws {
        let backend = BackendSpy(reply: .success("ask me about docks."))
        let answer = try await router(backend: backend).answer("tell me a joke")
        #expect(answer.text == "ask me about docks.")
        #expect(answer.source == .server)
        let question = try #require(await backend.questions.first)
        #expect(question.text == "tell me a joke")
        #expect(question.sessionID == "app-test")
        #expect(question.location != nil)
    }

    @Test func placesNotFoundOnDeviceFallBackToTheBackend() async throws {
        let backend = BackendSpy(reply: .success("Mercer and Bleecker has 29 docks open."))
        let answer = try await router(backend: backend).answer("find a dock near that bagel place by stern")
        #expect(answer.source == .server)
        #expect(await backend.questions.count == 1)
    }

    @Test func withoutABackendUnknownRequestsGetHelp() async throws {
        let answer = try await router().answer("tell me a joke")
        #expect(answer.text == AssistantRouter.helpText)
    }

    @Test func withoutABackendPlaceErrorsAreReported() async {
        await #expect(throws: DockFinderError.placeNotFound("atlantis")) {
            try await router().answer("find a dock near atlantis")
        }
    }

    @Test func backendFailuresAreReported() async {
        let backend = BackendSpy(reply: .failure(.backendUnavailable))
        await #expect(throws: DockFinderError.backendUnavailable) {
            try await router(backend: backend).answer("tell me a joke")
        }
    }
}

// MARK: - n8n client

struct N8NAssistantClientTests {
    @Test func endpointFromHost() {
        #expect(N8NAssistantClient.endpoint(forHost: "team.app.n8n.cloud")?.absoluteString == "https://team.app.n8n.cloud/webhook/citibike-siri")
        #expect(N8NAssistantClient.endpoint(forHost: "http://localhost:5678/")?.absoluteString == "http://localhost:5678/webhook/citibike-siri")
        #expect(N8NAssistantClient.endpoint(forHost: "") == nil)
        #expect(N8NAssistantClient.endpoint(forHost: "$(DOCKFINDER_BACKEND_HOST)") == nil)
    }

    @Test func sendsTheSameBodyAsTheSiriShortcut() async throws {
        let captured = RequestBox()
        let client = N8NAssistantClient(endpoint: URL(string: "https://example.com/webhook/citibike-siri")!) { request in
            await captured.set(request)
            return (Data("  your usual dock has 25 docks open.\n".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let reply = try await client.ask("hi", location: CLLocation(latitude: 40.5, longitude: -73.5), sessionID: "app-1")
        #expect(reply == "Your usual dock has 25 docks open.")

        let request = try #require(await captured.request)
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["text": "hi", "lat": "40.5", "lon": "-73.5", "sessionId": "app-1"])
    }

    @Test func serverErrorsAreBackendUnavailable() async {
        let client = N8NAssistantClient(endpoint: URL(string: "https://example.com/x")!) { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: DockFinderError.backendUnavailable) {
            try await client.ask("hi", location: nil, sessionID: "a")
        }
    }
}

private actor RequestBox {
    var request: URLRequest?
    func set(_ request: URLRequest) { self.request = request }
}

// MARK: - Saved places

@MainActor
struct SavedPlacesStoreTests {
    @Test func placesPersistAndNotifySiri() {
        let defaults = UserDefaults(suiteName: "SavedPlacesStoreTests-\(UUID())")!
        var changes = 0
        let store = SavedPlacesStore(defaults: defaults, onChange: { changes += 1 })
        let school = SavedPlace(name: "School", latitude: 40.7, longitude: -73.9)
        store.add(school)
        store.setUsualDock(stationID: "near", stationName: "Smith St & Bergen St", for: school.id)

        let reloaded = SavedPlacesStore(defaults: defaults, onChange: {})
        #expect(reloaded.places.count == 1)
        #expect(reloaded.places.first?.usualStationID == "near")
        #expect(reloaded.place(matching: "my school")?.id == school.id)
        #expect(changes == 2)

        store.remove(id: school.id)
        #expect(SavedPlacesStore(defaults: defaults, onChange: {}).places.isEmpty)
    }
}

// MARK: - "Run Dock Finder" follow-up answers

struct FollowUpAnswerTests {
    @Test(arguments: [
        ("find me a doc near union square", ParsedRequest.place("union square")),
        ("is there a doc by school", .place("school")),
        ("nearest doc", .nearMe),
        ("here", .nearMe),
        ("Near me.", .nearMe),
        ("nearest", .nearMe),
    ])
    func dictationQuirksAndShortAnswers(request: String, expected: ParsedRequest) {
        #expect(KeywordRequestParser.parse(request) == expected)
    }

    @Test func doctorIsNotRewritten() {
        #expect(KeywordRequestParser.normalize("find a doctor") == "find a doctor")
    }

    private let directory = [
        info("1", "Mercer St & Bleecker St", 40.7271, -73.9965),
        info("2", "Broadway & W 60 St", 40.7695, -73.9819),
        info("3", "Broadway & E 14 St", 40.7345, -73.9907),
        info("4", "Broadway", 40.7000, -73.9900),
    ]

    private var parser: ShortAnswerParser {
        ShortAnswerParser(
            savedPlaces: [SavedPlace(name: "School", latitude: 40.729, longitude: -73.996)],
            service: DockFinderService(
                location: StubLocation(result: .failure(.locationUnavailable)),
                feeds: StubFeeds(information: .success(informationFeed(directory)), status: .failure(.networkUnavailable)),
                now: { referenceNow }
            )
        )
    }

    @Test func savedPlaceNamesAlone() async {
        #expect(await parser.parse("School") == .place("school"))
        #expect(await parser.parse("my school") == .place("my school"))
    }

    @Test func stationNamesAlone() async {
        #expect(await parser.parse("Mercer and Bleecker") == .station("1"))
        #expect(await parser.parse("Mercer and Bleeker") == .station("1"))
        #expect(await parser.parse("broadway and east 14th") == .station("3"))
    }

    @Test func ambiguousOrUnrelatedAnswersAreLeftForTheNextStep() async {
        #expect(await parser.parse("mercer") == nil, "one word only counts if it's a station's whole name")
        #expect(await parser.parse("broadway") == .station("4"))
        #expect(await parser.parse("tell me a joke") == nil)
        #expect(await parser.parse("") == nil)
    }
}
