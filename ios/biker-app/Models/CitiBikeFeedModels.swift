//
//  CitiBikeFeedModels.swift
//  Dock Finder
//
//  Typed models for the Citi Bike GBFS `station_information` and
//  `station_status` feeds.
//

import Foundation

/// Top-level GBFS envelope shared by every feed.
nonisolated struct GBFSFeed<Payload: Decodable & Sendable>: Decodable, Sendable {
    /// When the publisher last refreshed the feed.
    let lastUpdated: Date
    /// Seconds the publisher says the data stays valid.
    let ttl: Int
    let data: Payload

    private enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }

    init(lastUpdated: Date, ttl: Int, data: Payload) {
        self.lastUpdated = lastUpdated
        self.ttl = ttl
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Double.self, forKey: .lastUpdated)
        lastUpdated = Date(timeIntervalSince1970: timestamp)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl) ?? 0
        data = try container.decode(Payload.self, forKey: .data)
    }
}

nonisolated struct StationInformationPayload: Decodable, Sendable {
    let stations: [StationInformation]

    init(stations: [StationInformation]) {
        self.stations = stations
    }

    private enum CodingKeys: String, CodingKey { case stations }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A single malformed station should not take down the whole feed.
        stations = try container.decode([Lossy<StationInformation>].self, forKey: .stations)
            .compactMap(\.value)
    }
}

nonisolated struct StationStatusPayload: Decodable, Sendable {
    let stations: [StationStatus]

    init(stations: [StationStatus]) {
        self.stations = stations
    }

    private enum CodingKeys: String, CodingKey { case stations }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stations = try container.decode([Lossy<StationStatus>].self, forKey: .stations)
            .compactMap(\.value)
    }
}

/// Static station metadata from `station_information.json`.
nonisolated struct StationInformation: Decodable, Sendable, Equatable {
    let stationID: String
    let name: String
    let latitude: Double
    let longitude: Double

    private enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case name
        case latitude = "lat"
        case longitude = "lon"
    }

    init(stationID: String, name: String, latitude: Double, longitude: Double) {
        self.stationID = stationID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Live availability from `station_status.json`.
nonisolated struct StationStatus: Decodable, Sendable, Equatable {
    let stationID: String
    let numDocksAvailable: Int
    let isInstalled: Bool
    let isReturning: Bool
    /// When the station itself last reported to the system, if present.
    let lastReported: Date?

    private enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case numDocksAvailable = "num_docks_available"
        case isInstalled = "is_installed"
        case isReturning = "is_returning"
        case lastReported = "last_reported"
    }

    init(stationID: String, numDocksAvailable: Int, isInstalled: Bool, isReturning: Bool, lastReported: Date?) {
        self.stationID = stationID
        self.numDocksAvailable = numDocksAvailable
        self.isInstalled = isInstalled
        self.isReturning = isReturning
        self.lastReported = lastReported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationID = try container.decode(String.self, forKey: .stationID)
        numDocksAvailable = try container.decode(Int.self, forKey: .numDocksAvailable)
        // The spec says booleans, but Citi Bike publishes 0/1 integers.
        isInstalled = try container.decodeFlexibleBool(forKey: .isInstalled)
        isReturning = try container.decodeFlexibleBool(forKey: .isReturning)
        lastReported = try container.decodeIfPresent(Double.self, forKey: .lastReported)
            .map(Date.init(timeIntervalSince1970:))
    }
}

/// Decodes an element, yielding `nil` instead of throwing if it is malformed.
nonisolated private struct Lossy<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

nonisolated private extension KeyedDecodingContainer {
    func decodeFlexibleBool(forKey key: Key) throws -> Bool {
        if let bool = try? decode(Bool.self, forKey: key) {
            return bool
        }
        if let int = try? decode(Int.self, forKey: key) {
            return int != 0
        }
        if let string = try? decode(String.self, forKey: key) {
            switch string.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: break
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            .init(codingPath: codingPath + [key], debugDescription: "Expected a boolean, 0/1, or \"true\"/\"false\".")
        )
    }
}
