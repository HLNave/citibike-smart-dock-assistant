//
//  AssistantRouter.swift
//  Dock Finder
//
//  Answers a free-form request. Everything that can be answered on device
//  is; the n8n backend is only asked when no on-device parser understands
//  the request, or when the place or station it names can't be found on
//  device. Before giving up on a place or station, Apple's on-device model
//  (where available) gets one more try at finding it (OnDeviceRecovery).
//  That second try also covers the Siri actions that call `handle(_:)`.
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
    var guidance: any GuidanceControlling = GuidanceSession.shared
    /// Rewrites a place the map can't find. `nil`: no second try.
    var placeRewriter: (any PlaceQueryRewriting)? = nil
    /// Picks the station meant when no name matches. `nil`: no second try.
    var stationPicker: (any StationPicking)? = nil
    /// How long either second try may take.
    var recoveryTimeLimit: Duration = OnDeviceRecovery.timeLimit

    static let helpText = "You can ask whether a station has room, like is Mercer and Bleecker full, or how many bikes are out. To get docking directions on the way somewhere, say start a ride to school."
    static let stoppedDirections = "Okay, I stopped the directions."

    /// Names riders use for their own places. If one isn't saved, a map
    /// search would find some business called "Home" or "Gym" instead.
    static let personalPlaceNames: Set<String> = [
        "home", "work", "school", "office", "the office", "gym", "class", "campus", "job",
        "my place", "apartment", "house", "dorm", "my dorm",
    ]

    static func live() -> AssistantRouter {
        let service = DockFinderService.live
        let store = SavedPlacesStore.shared
        return AssistantRouter(
            service: service,
            placeSearch: MapKitPlaceSearch(),
            store: store,
            rides: RideTracker.shared,
            // Apple's model first, so a request is understood however it's
            // worded; the phrase rules catch what it can't (or every
            // request, on iPhones without Apple Intelligence).
            parsers: [
                OnDeviceModelParser(savedPlaceNames: store.places.flatMap(\.spokenNames)),
                KeywordRequestParser(),
                ShortAnswerParser(savedPlaces: store.places, service: service),
            ],
            backend: N8NAssistantClient.configured(),
            location: LocationService.shared,
            sessionID: AssistantSession.id(),
            placeRewriter: OnDeviceModelPlaceRewriter(),
            stationPicker: OnDeviceModelStationPicker()
        )
    }

    var savedPlaces: [SavedPlace] { store.places }

    func answer(_ text: String) async throws -> DockAnswer {
        for candidate in parsers {
            guard var request = await candidate.parse(text) else { continue }
            var parser: any RequestParsing = candidate
            // Apple's model sometimes reads "direct me to school" as plain
            // "direct me" or "near me", which ends at the nearest dock.
            // When the phrase rules found something more specific, they win.
            if parser.answeredBy == .appleIntelligence, request.isGeneric,
               let rule = KeywordRequestParser.parse(text), !rule.isGeneric {
                request = rule
                parser = KeywordRequestParser()
            }
            // What was heard and what it became, so a wrong answer can be
            // traced in the team's sheet.
            Metrics.shared.log("request_understood", details: [
                "text": text,
                "answered_by": parser.answeredBy.rawValue,
                "request": String(describing: request),
            ])
            // A place Apple's model already wrote isn't worth asking it to rewrite.
            var router = self
            if parser.answeredBy == .appleIntelligence {
                router.placeRewriter = nil
            }
            do {
                var answer = try await router.handle(request)
                // Unless Apple's model found the place or station, the
                // parser is what understood it.
                if answer.answeredBy == .fixedAction {
                    answer.markAnswered(by: parser.answeredBy)
                }
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
            let found = try await searchedDestination(spoken)
            var answer = try await service.findDock(near: found.destination).answer
            if found.rewritten { answer.markAnswered(by: .appleIntelligence) }
            return answer

        case .station(let spoken):
            if let saved = savedPlaceForDock(spoken) {
                guard let stationID = saved.usualStationID else {
                    return DockAnswer(text: "You haven't set a usual dock for \(saved.name) yet. Pick one under \(saved.name) in Dock Finder.")
                }
                return try await service.checkStation(stationID).answer
            }
            return try await checkStation(named: spoken)

        case .startRide(let spoken):
            return try await startRide(to: spoken)

        case .endRide:
            guard let ride = rides.currentRide else {
                if guidance.isActive {
                    await guidance.stop()
                    return DockAnswer(text: Self.stoppedDirections)
                }
                return DockAnswer(text: "You don't have a ride in progress.")
            }
            await rides.end()
            await guidance.stop()
            return DockAnswer(text: "Okay, I stopped watching your ride to \(ride.destination.name).")

        case .directions:
            let station: DockStation
            if let offered = guidance.recentOffer(now: .now) {
                station = offered
            } else {
                station = try await service.findNearestDock().station
            }
            return try await startDirections(to: station)

        case .directionsTo(let spoken):
            // The best dock there, the same one "check my school dock" or
            // "find a dock near Union Square" names.
            let result: DestinationDockResult
            var rewritten = false
            if let saved = store.place(matching: spoken) {
                result = try await service.findDock(for: saved)
            } else {
                let found = try await searchedDestination(spoken)
                rewritten = found.rewritten
                result = try await service.findDock(near: found.destination)
            }
            // No dock with room there: the answer says so.
            guard let station = result.selected else { return result.answer }
            var answer = try await startDirections(to: station)
            if rewritten { answer.markAnswered(by: .appleIntelligence) }
            return answer

        case .stopDirections:
            if guidance.isActive {
                await guidance.stop()
                return DockAnswer(text: Self.stoppedDirections)
            }
            if let ride = rides.currentRide, ride.guidesToDock {
                rides.setGuidesToDock(false)
                return DockAnswer(text: "Okay. On this ride, I'll just tell you where to dock.")
            }
            return DockAnswer(text: "You're not getting directions right now.")

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

    // MARK: - Directions

    private func startDirections(to station: DockStation) async throws -> DockAnswer {
        let siriLine = guidance.siriConfirmation(for: station)
        let reply = try await guidance.start(to: station, siriWillSay: siriLine)
        return DockAnswer(text: guidance.isActive ? siriLine : reply)
    }

    // MARK: - Rides

    private func startRide(to answer: String) async throws -> DockAnswer {
        let spoken = KeywordRequestParser.destination(from: answer)
        guard !spoken.isEmpty else {
            return DockAnswer(text: "Where are you heading? Say, for example, ask Dock Finder to start a ride to school.")
        }

        let ride: Ride
        var rewritten = false
        if let saved = store.place(matching: spoken) {
            ride = Ride(destination: saved.destination, savedPlaceID: saved.id, alertDistance: saved.alertDistance)
        } else if Self.personalPlaceNames.contains(spoken) || spoken.hasPrefix("my ") {
            let name = SavedPlace.normalizedName(spoken)
            return DockAnswer(text: "You don't have a saved place called \(name). Add it in Dock Finder, or say an address or landmark instead.")
        } else {
            let found = try await searchedDestination(spoken)
            ride = Ride(destination: found.destination)
            rewritten = found.rewritten
        }

        var answer = try await begin(ride)
        if rewritten { answer.markAnswered(by: .appleIntelligence) }
        return answer
    }

    /// Starts watching `ride`, or answers right away when the rider is already there.
    private func begin(_ ride: Ride) async throws -> DockAnswer {
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
        return DockAnswer(text: "Saved this spot as \(name). Next time, ask Dock Finder to start a ride to \(name).")
    }

    // MARK: - Helpers

    /// When no station's name is close enough, Apple's model gets to pick
    /// which of the closest names the rider meant ("mercy and bleaker").
    private func checkStation(named spoken: String) async throws -> DockAnswer {
        let network = try await service.loadNetwork()
        if let station = network.bestMatch(for: spoken) {
            return DockFinderService.check(station, in: network).answer
        }
        guard let stationPicker else { throw DockFinderError.stationNotFound(spoken) }
        let candidates = await stationCandidates(for: spoken, in: network)
        let choices = candidates.map { StationChoice(id: $0.id, name: $0.name) }
        guard !choices.isEmpty,
              let id = await withTimeLimit(recoveryTimeLimit, { await stationPicker.pick(spoken, from: choices) }),
              let station = candidates.first(where: { $0.id == id })
        else { throw DockFinderError.stationNotFound(spoken) }
        var answer = DockFinderService.check(station, in: network).answer
        answer.markAnswered(by: .appleIntelligence)
        return answer
    }

    /// What the model chooses from: names like what was said, or failing
    /// that, the stations the rider most likely means: their saved places'
    /// docks, then the ones nearest them.
    private func stationCandidates(for spoken: String, in network: StationNetwork) async -> [StationSnapshot] {
        let similar = StationNameMatcher.shortlist(for: spoken, in: network.stations)
        guard similar.isEmpty else { return similar }
        var ids = savedPlaces.flatMap { [$0.usualStationID, $0.backupStationID] }.compactMap { $0 }
        let location = location
        if let here = await withTimeLimit(recoveryTimeLimit, { try? await location.currentLocation().location }) {
            ids += network.stations
                .sorted { here.distance(from: $0.location) < here.distance(from: $1.location) }
                .prefix(8)
                .map(\.id)
        }
        var seen: Set<String> = []
        return Array(ids.filter { seen.insert($0).inserted }.compactMap(network.station(id:)).prefix(8))
    }

    /// Speaks the rider's own words ("from union square"), not the map's
    /// formal name ("from Union Square Park"), even when Apple's model
    /// rewrote the search (`rewritten`).
    private func searchedDestination(_ spoken: String) async throws -> (destination: Destination, rewritten: Bool) {
        let found = try await placeSearch.search(spoken, rewritingWith: placeRewriter, timeLimit: recoveryTimeLimit)
        guard let match = found.places.first else {
            throw DockFinderError.placeNotFound(spoken)
        }
        let destination = Destination(name: spoken, latitude: match.latitude, longitude: match.longitude, address: match.address)
        return (destination, found.rewrittenQuery != nil)
    }

    private func askBackend(_ text: String, otherwise error: DockFinderError?) async throws -> DockAnswer {
        guard let backend else {
            if let error { throw error }
            return DockAnswer(text: Self.helpText)
        }
        let here = try? await location.currentLocation().location
        do {
            let reply = try await backend.ask(text, location: here, sessionID: sessionID)
            var answer = DockAnswer(text: reply)
            answer.markAnswered(by: .server)
            return answer
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
