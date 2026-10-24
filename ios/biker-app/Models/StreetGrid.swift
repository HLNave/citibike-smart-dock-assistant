//
//  StreetGrid.swift
//  Dock Finder
//
//  A rough walking or riding distance that follows Manhattan's street grid
//  instead of cutting across blocks. Used to rank docks, not to speak
//  distances: spoken distances stay straight-line.
//

import CoreLocation
import Foundation

nonisolated enum StreetGrid {
    /// Manhattan's avenues run about 29° east of true north.
    static let avenueBearing = 29.0 * Double.pi / 180
    private static let metersPerDegreeLatitude = 111_320.0

    /// Distance along the avenues and cross streets when both points are on
    /// Manhattan's grid; otherwise the straight-line distance.
    static func distance(from start: CLLocation, to end: CLLocation) -> CLLocationDistance {
        let a = start.coordinate
        let b = end.coordinate
        guard isOnGrid(a), isOnGrid(b) else { return start.distance(from: end) }
        let middleLatitude = (a.latitude + b.latitude) / 2 * Double.pi / 180
        let north = (b.latitude - a.latitude) * metersPerDegreeLatitude
        let east = (b.longitude - a.longitude) * metersPerDegreeLatitude * cos(middleLatitude)
        let alongAvenues = north * cos(avenueBearing) + east * sin(avenueBearing)
        let alongStreets = east * cos(avenueBearing) - north * sin(avenueBearing)
        return abs(alongAvenues) + abs(alongStreets)
    }

    /// Whether a point is in the part of Manhattan with a regular grid:
    /// north of Houston St, leaving out the West Village below about 12th St
    /// west of Sixth Avenue. Lower Manhattan's streets don't follow a grid.
    static func isOnGrid(_ point: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var previous = gridOutline[gridOutline.count - 1]
        for current in gridOutline {
            let crosses = (current.latitude > point.latitude) != (previous.latitude > point.latitude)
            if crosses {
                let longitudeAtPoint = current.longitude
                    + (point.latitude - current.latitude) * (previous.longitude - current.longitude)
                    / (previous.latitude - current.latitude)
                if point.longitude < longitudeAtPoint { inside.toggle() }
            }
            previous = current
        }
        return inside
    }

    /// The gridded area's outline, roughly following the shorelines,
    /// Houston St, and the West Village's edge.
    private static let gridOutline: [CLLocationCoordinate2D] = gridOutlinePoints.map {
        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    }

    private static let gridOutlinePoints: [(latitude: Double, longitude: Double)] = [
        (40.7185, -73.9740), // Houston St at the East River
        (40.7290, -73.9710), // East 14th St
        (40.7440, -73.9715), // East 34th St
        (40.7590, -73.9580), // East 60th St
        (40.7835, -73.9410), // East 96th St
        (40.8010, -73.9290), // Harlem River at 125th St
        (40.8300, -73.9330), // Harlem River at 155th St
        (40.8740, -73.9110), // Inwood
        (40.8790, -73.9260), // Spuyten Duyvil
        (40.8510, -73.9530), // Hudson at the George Washington Bridge
        (40.8200, -73.9610), // Hudson at 125th St
        (40.7990, -73.9770), // Hudson at 96th St
        (40.7710, -73.9950), // Hudson at 57th St
        (40.7560, -74.0080), // Hudson at 34th St
        (40.7395, -74.0105), // Hudson near Gansevoort St
        (40.7355, -73.9975), // Sixth Avenue at 12th St
        (40.7280, -74.0020), // Sixth Avenue at Houston St
    ]
}
