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
    var store: SavedPlacesStore
    var rides: any RideControlling
    /// Tried in order; the first one that understands the request wins.
    var parsers: [any RequestParsing]
    var backend: (any AssistantBackend)?
    var location: any LocationProviding
    var sessionID: String

    static let helpText = "Say where you're headed, like school or Union Square, a station name, or near me. You can also say start a ride to school."

    static func live() -> AssistantRouter {
        let service = DockFinderService.live
        let store = SavedPlacesStore.shared
        return AssistantRouter(
            service: service,
            placeSearch: MapKitPlaceSearch(),
            store: store,
            rides: RideTracker.shared,
            parsers: [
                KeywordRequestParser(),
                ShortAnswerParser(savedPlaces: store.places, service: service),
                OnDeviceModelParser(),
            ],
            backend: N8NAssistantClient.configured(),
            location: LocationService.shared,
            sessionID: AssistantSession.id()
        )
    }

    var savedPlaces: [SavedPlace] { store.places }

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
            if let saved = store.place(matching: spoken) {
                return try await service.findDock(for: saved).answer
            }
            let destination = try await searchedDestination(spoken)
            return try await service.findDock(near: destination).answer

        case .station(let spoken):
            if let saved = savedPlaceForDock(spoken) {
                guard let stationID = saved.usualStationID else {
                    return DockAnswer(text: "You haven't set a usual dock for \(saved.name) yet. Say, for example, my \(saved.name.lowercased()) dock is Mercer and Bleecker.")
                }
                return try await service.checkStation(stationID).answer
            }
            return try await service.checkStation(spoken).answer

        case .startRide(let spoken):
            return try await startRide(to: spoken)

        case .endRide:
            guard let ride = rides.currentRide else {
                return DockAnswer(text: "You don't have a ride in progress.")
            }
            await rides.end()
            return DockAnswer(text: "Okay, I stopped watching your ride to \(ride.destination.name).")

        case .setUsualDock(let placeName, let stationName):
            guard let saved = store.place(matching: placeName) else {
                return DockAnswer(text: "You don't have a saved place called \(placeName). Open Dock Finder to add it first.")
            }
            let network = try await service.loadNetwork()
            guard let station = network.bestMatch(for: stationName) else {
                throw DockFinderError.stationNotFound(stationName)
            }
            store.setUsualDock(stationID: station.id, stationName: station.name, for: saved.id)
            return DockAnswer(text: "Got it. \(station.spokenName) is your \(saved.name.lowercased()) dock.")

        case .savePlace(let name):
            return try await savePlace(named: name)
        }
    }

    // MARK: - Rides

    private func startRide(to spoken: String) async throws -> DockAnswer {
        guard !spoken.isEmpty else {
            return DockAnswer(text: "Where are you riding to? Say, for example, start a ride to school.")
        }

        let ride: Ride
        if let saved = store.place(matching: spoken) {
            ride = Ride(destination: saved.destination, savedPlaceID: saved.id, alertDistance: saved.alertDistance)
        } else {
            ride = Ride(destination: try await searchedDestination(spoken))
        }

        // Already close: answer now instead of watching for an arrival that won't come.
        if let here = try? await location.currentLocation().location,
           here.distance(from: ride.destination.location) <= ride.alertDistance {
            if let id = ride.savedPlaceID, let saved = store.place(id: id) {
                return try await service.findDock(for: saved).answer
            }
            return try await service.findDock(near: ride.destination).answer
        }

        await rides.start(ride)
        var text = "Got it. I'll tell you where to dock when you're about \(Speech.length(ride.alertDistance)) from \(ride.destination.name)."
        if !rides.canTrackInBackground {
            text += " To get this with your phone locked, open Dock Finder and allow location access all the time."
        }
        return DockAnswer(text: text)
    }

    // MARK: - Saved places

    private func savePlace(named name: String) async throws -> DockAnswer {
        if let problem = store.validate(name: name) {
            return DockAnswer(text: String(localized: problem.localizedStringResource))
        }
        let here = try await location.currentLocation().location
        let address = await placeSearch.address(for: here)
        let displayName = name.prefix(1).uppercased() + name.dropFirst()
        store.add(SavedPlace(name: displayName, latitude: here.coordinate.latitude, longitude: here.coordinate.longitude, address: address))
        return DockAnswer(text: "Saved this spot as \(name). Next time, say start a ride to \(name).")
    }

    // MARK: - Helpers

    /// Speaks the rider's own words ("from union square"), not the map's
    /// formal name ("from Union Square Park").
    private func searchedDestination(_ spoken: String) async throws -> Destination {
        guard let match = try await placeSearch.search(spoken).first else {
            throw DockFinderError.placeNotFound(spoken)
        }
        return Destination(name: spoken, latitude: match.latitude, longitude: match.longitude, address: match.address)
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

    /// "my school dock", "school dock", "my usual school dock" → the school place.
    private func savedPlaceForDock(_ spoken: String) -> SavedPlace? {
        let name = SavedPlace.normalizedName(spoken)
        if name.isEmpty || name == "dock" || name == "station" {
            // "my usual dock" is only unambiguous with a single saved place.
            return savedPlaces.count == 1 ? savedPlaces.first : nil
        }
        return store.place(matching: name)
    }
}
