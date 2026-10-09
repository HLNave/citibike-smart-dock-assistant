//
//  AssistantRouter.swift
//  Dock Finder
//
//  Answers a free-form request. Everything that can be answered on device
//  is; the n8n backend is only asked when neither on-device parser
//  understands the request, or when the place or station it names can't
//  be found on device.
//

import CoreLocation
import Foundation

struct AssistantRouter {
    var service: DockFinderService
    var placeSearch: any PlaceSearching
    var savedPlaces: [SavedPlace]
    /// Tried in order; the first one that understands the request wins.
    var parsers: [any RequestParsing]
    var backend: (any AssistantBackend)?
    var location: any LocationProviding
    var sessionID: String

    static let helpText = "Say where you're headed, like school or Union Square, a station name, or near me. You can also ask how many bikes are out."

    static func live() -> AssistantRouter {
        let service = DockFinderService.live
        let savedPlaces = SavedPlacesStore.shared.places
        return AssistantRouter(
            service: service,
            placeSearch: MapKitPlaceSearch(),
            savedPlaces: savedPlaces,
            parsers: [
                KeywordRequestParser(),
                ShortAnswerParser(savedPlaces: savedPlaces, service: service),
                OnDeviceModelParser(),
            ],
            backend: N8NAssistantClient.configured(),
            location: LocationService.shared,
            sessionID: AssistantSession.id()
        )
    }

    func answer(_ text: String) async throws -> DockAnswer {
        for parser in parsers {
            guard let request = await parser.parse(text) else { continue }
            do {
                var answer = try await handle(request)
                answer.source = parser.answerSource
                return answer
            } catch DockFinderError.placeNotFound(let query) {
                // The backend's AI rewrite may still find it ("that bagel place by Stern").
                return try await askBackend(text, otherwise: .placeNotFound(query))
            } catch DockFinderError.stationNotFound(let query) {
                return try await askBackend(text, otherwise: .stationNotFound(query))
            }
        }
        return try await askBackend(text, otherwise: nil)
    }

    func handle(_ request: ParsedRequest) async throws -> DockAnswer {
        switch request {
        case .nearMe:
            return try await service.findNearestDock().answer

        case .citywide:
            return try await service.citywideSummary().answer

        case .place(let spoken):
            if let saved = savedPlace(for: spoken) {
                return try await service.findDock(near: saved.destination, usualStationID: saved.usualStationID).answer
            }
            guard let match = try await placeSearch.search(spoken).first else {
                throw DockFinderError.placeNotFound(spoken)
            }
            // Speak the rider's own words ("from union square"), not the map's
            // formal name ("from Union Square Park").
            let destination = Destination(name: spoken, latitude: match.latitude, longitude: match.longitude, address: match.address)
            return try await service.findDock(near: destination).answer

        case .station(let spoken):
            if let saved = savedPlaceForDock(spoken) {
                guard let stationID = saved.usualStationID else {
                    return DockAnswer(text: "You haven't set a usual dock for \(saved.name) yet. Open Dock Finder to pick one.")
                }
                return try await service.checkStation(stationID).answer
            }
            return try await service.checkStation(spoken).answer
        }
    }

    private func askBackend(_ text: String, otherwise error: DockFinderError?) async throws -> DockAnswer {
        guard let backend else {
            if let error { throw error }
            return DockAnswer(text: Self.helpText)
        }
        let here = try? await location.currentLocation().location
        do {
            let reply = try await backend.ask(text, location: here, sessionID: sessionID)
            return DockAnswer(text: reply, source: .server)
        } catch {
            throw error as? DockFinderError ?? .backendUnavailable
        }
    }

    private func savedPlace(for spoken: String) -> SavedPlace? {
        savedPlaces.first { $0.matches(spoken) }
    }

    /// "my school dock", "school dock", "my usual school dock" → the school place.
    private func savedPlaceForDock(_ spoken: String) -> SavedPlace? {
        var name = spoken.lowercased()
        for word in [" dock", " station"] where name.hasSuffix(word) {
            name.removeLast(word.count)
        }
        name = name.replacingOccurrences(of: "usual ", with: "")
        if name == "my" || name == "my usual" {
            // "my usual dock" is only unambiguous with a single saved place.
            return savedPlaces.count == 1 ? savedPlaces.first : nil
        }
        return savedPlace(for: name)
    }
}
