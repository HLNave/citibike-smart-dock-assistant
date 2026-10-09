//
//  DockFinderError.swift
//  Dock Finder
//

import Foundation

/// Every failure a dock search can produce. Messages are written to be
/// spoken by Siri as well as shown in the app.
nonisolated enum DockFinderError: Error, Equatable, Sendable {
    case locationPermissionNotDetermined
    case locationPermissionDenied
    case locationRestricted
    case locationUnavailable
    case networkUnavailable
    case serviceUnavailable(statusCode: Int)
    case malformedData
    case noStationData
    case staleData(lastUpdated: Date)
    case noAvailableDocks
    case outsideServiceArea
}

extension DockFinderError: CustomLocalizedStringResourceConvertible, LocalizedError {
    nonisolated var localizedStringResource: LocalizedStringResource {
        switch self {
        case .locationPermissionNotDetermined:
            "Dock Finder needs your location. Open Dock Finder and tap Enable Dock Finder with Siri to allow location access."
        case .locationPermissionDenied:
            "Dock Finder doesn't have permission to use your location. Open Dock Finder to allow location access in Settings."
        case .locationRestricted:
            "Location access is restricted on this device, so Dock Finder can't find docks near you."
        case .locationUnavailable:
            "Dock Finder couldn't determine your location right now. Try again in a moment."
        case .networkUnavailable:
            "Dock Finder couldn't reach Citi Bike. Check your internet connection and try again."
        case .serviceUnavailable:
            "Citi Bike's station data is temporarily unavailable. Try again shortly."
        case .malformedData:
            "Citi Bike returned station data that Dock Finder couldn't read. Try again shortly."
        case .noStationData:
            "Citi Bike didn't return any station data right now. Try again shortly."
        case .staleData:
            "Citi Bike's live availability data is out of date, so Dock Finder can't give a reliable answer right now."
        case .noAvailableDocks:
            "Dock Finder couldn't find a Citi Bike station with an open dock right now."
        case .outsideServiceArea:
            "There are no Citi Bike stations with open docks near you. Citi Bike operates in New York City, Jersey City, and Hoboken."
        }
    }

    nonisolated var errorDescription: String? {
        String(localized: localizedStringResource)
    }
}
