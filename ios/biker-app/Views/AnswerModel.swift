//
//  AnswerModel.swift
//  Dock Finder
//
//  Runs one lookup at a time for a screen and holds its outcome. Every
//  screen goes through the same DockFinderService that Siri uses.
//

import CoreLocation
import Observation

@Observable
final class AnswerModel {
    enum Phase: Equatable {
        case idle
        case loading
        case answered(DockAnswer)
        case failed(DockFinderError)
    }

    private(set) var phase: Phase = .idle

    var isLoading: Bool { phase == .loading }

    /// Ignored while a lookup is already in flight, so repeated taps or
    /// view refreshes never stack network requests.
    func run(needsLocation: Bool = false, _ operation: @escaping () async throws -> DockAnswer) async {
        guard phase != .loading else { return }
        phase = .loading

        // This runs from a button tap, so it's an appropriate moment to ask.
        if needsLocation, LocationService.shared.authorizationStatus == .notDetermined {
            _ = await LocationService.shared.requestWhenInUseAuthorization()
        }

        do {
            phase = .answered(try await operation())
        } catch let error as DockFinderError {
            phase = .failed(error)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(.networkUnavailable)
        }
    }

    func reset() {
        phase = .idle
    }
}
