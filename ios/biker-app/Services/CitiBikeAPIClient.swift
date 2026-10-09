//
//  CitiBikeAPIClient.swift
//  Dock Finder
//
//  Fetches Citi Bike's public GBFS feeds.
//

import Foundation

/// Source of station metadata and live status. Abstracted for testing.
nonisolated protocol CitiBikeFeedProviding: Sendable {
    func fetchStationInformation() async throws -> GBFSFeed<StationInformationPayload>
    func fetchStationStatus() async throws -> GBFSFeed<StationStatusPayload>
}

nonisolated struct CitiBikeAPIClient: CitiBikeFeedProviding {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let stationInformationURL = URL(string: "https://gbfs.citibikenyc.com/gbfs/en/station_information.json")!
    static let stationStatusURL = URL(string: "https://gbfs.citibikenyc.com/gbfs/en/station_status.json")!

    private let loadData: DataLoader
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15, loadData: @escaping DataLoader = { try await URLSession.shared.data(for: $0) }) {
        self.timeout = timeout
        self.loadData = loadData
    }

    @concurrent
    func fetchStationInformation() async throws -> GBFSFeed<StationInformationPayload> {
        try await fetch(Self.stationInformationURL)
    }

    @concurrent
    func fetchStationStatus() async throws -> GBFSFeed<StationStatusPayload> {
        try await fetch(Self.stationStatusURL)
    }

    @concurrent
    private func fetch<Payload>(_ url: URL) async throws -> GBFSFeed<Payload> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loadData(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw DockFinderError.networkUnavailable
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DockFinderError.serviceUnavailable(statusCode: http.statusCode)
        }
        return try Self.decode(data)
    }

    /// Decodes a GBFS feed, mapping any failure to `DockFinderError.malformedData`.
    static func decode<Payload>(_ data: Data) throws -> GBFSFeed<Payload> {
        do {
            return try JSONDecoder().decode(GBFSFeed<Payload>.self, from: data)
        } catch {
            throw DockFinderError.malformedData
        }
    }
}

/// Keeps station metadata (names and locations) for an hour, since it
/// rarely changes and is the larger of the two feeds. Live status is
/// always fetched fresh.
actor CachedStationFeeds: CitiBikeFeedProviding {
    static let shared = CachedStationFeeds(base: CitiBikeAPIClient())

    private static let informationLifetime: TimeInterval = 60 * 60

    private let base: any CitiBikeFeedProviding
    private var cachedInformation: (feed: GBFSFeed<StationInformationPayload>, fetchedAt: Date)?

    init(base: any CitiBikeFeedProviding) {
        self.base = base
    }

    func fetchStationInformation() async throws -> GBFSFeed<StationInformationPayload> {
        if let cachedInformation, -cachedInformation.fetchedAt.timeIntervalSinceNow < Self.informationLifetime {
            return cachedInformation.feed
        }
        let feed = try await base.fetchStationInformation()
        cachedInformation = (feed, Date())
        return feed
    }

    func fetchStationStatus() async throws -> GBFSFeed<StationStatusPayload> {
        try await base.fetchStationStatus()
    }
}
