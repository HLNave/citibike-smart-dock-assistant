//
//  DockLookupModel.swift
//  Dock Finder
//
//  Drives the in-app "Find Nearest Dock" / "Try Dock Finder" buttons using
//  the same DockFinderService that Siri uses.
//

import CoreLocation
import Observation

@Observable
final class DockLookupModel {
    enum Phase: Equatable {
        case idle
        case searching
        case found(DockSearchResult)
        case failed(DockFinderError)
    }

    private(set) var phase: Phase = .idle

    private let service: DockFinderService
    private let location: LocationService

    init(service: DockFinderService? = nil, location: LocationService? = nil) {
        self.service = service ?? .live
        self.location = location ?? .shared
    }

    /// Runs one lookup. Ignored while a lookup is already in flight, so
    /// repeated taps or view refreshes never stack network requests.
    func findNearestDock() async {
        guard phase != .searching else { return }
        phase = .searching

        // This runs from a button tap, so it's an appropriate moment to ask.
        if location.authorizationStatus == .notDetermined {
            _ = await location.requestWhenInUseAuthorization()
        }

        do {
            phase = .found(try await service.findNearestDock())
        } catch let error as DockFinderError {
            phase = .failed(error)
        } catch {
            phase = .idle
        }
    }
}
