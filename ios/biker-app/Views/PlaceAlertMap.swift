//
//  PlaceAlertMap.swift
//  Dock Finder
//
//  A saved place on a map: its pin, which the rider can drag or drop with
//  a tap, and its alert radius drawn to scale as a circle, with a slider
//  to change it. Nearby Citi Bike stations show as dots, with the usual
//  and backup docks labeled. The place's screen shows it read-only.
//

import CoreLocation
import MapKit
import SwiftUI

struct PlaceAlertMap: View {
    /// Where the place is; nil until the rider picks a spot.
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var alertDistance: CLLocationDistance
    /// What VoiceOver calls the pin: the place's name or address.
    let pinLabel: String
    let stations: [StationInformation]
    let usualStationID: String?
    let backupStationID: String?
    /// False for the preview: no dragging, tapping, panning or slider.
    let isEditable: Bool

    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion?
    /// Where the pin is while it's being dragged. The place only moves
    /// (and its address is looked up) when the drag ends.
    @State private var draggedCoordinate: CLLocationCoordinate2D?
    /// From the finger to the pin's tip, so the pin doesn't jump under the finger.
    @State private var dragOffset: CGSize?
    /// The last spot this view moved the pin to itself, to tell a tap or
    /// drag apart from a search or "Use My Current Location".
    @State private var ownMove: CLLocationCoordinate2D?
    @State private var isSliding = false
    @State private var userMovedCameraAt = Date.distantPast

    init(
        coordinate: Binding<CLLocationCoordinate2D?>,
        alertDistance: Binding<CLLocationDistance>,
        pinLabel: String,
        stations: [StationInformation] = [],
        usualStationID: String? = nil,
        backupStationID: String? = nil,
        isEditable: Bool = true
    ) {
        _coordinate = coordinate
        _alertDistance = alertDistance
        self.pinLabel = pinLabel
        self.stations = stations
        self.usualStationID = usualStationID
        self.backupStationID = backupStationID
        self.isEditable = isEditable
        _position = State(initialValue: coordinate.wrappedValue.map {
            .region(AlertMapGeometry.region(center: $0, radius: alertDistance.wrappedValue))
        } ?? .userLocation(fallback: .region(MapKitPlaceSearch.serviceRegion)))
    }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: isEditable ? 300 : 180)
            if isEditable {
                radiusControl
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Map

    private var pinCoordinate: CLLocationCoordinate2D? { draggedCoordinate ?? coordinate }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: isEditable ? [.pan, .zoom, .rotate] : []) {
                if let center = pinCoordinate {
                    // A fixed blue rather than the accent color, which
                    // iOS dims while a sheet covers the map, and MapKit
                    // keeps drawing it dimmed after the sheet closes.
                    MapCircle(center: center, radius: alertDistance)
                        .foregroundStyle(Color.blue.opacity(0.18))
                        .stroke(Color.blue, lineWidth: 2)
                }
                ForEach(nearbyStations, id: \.stationID) { station in
                    Annotation(station.name, coordinate: station.coordinate) {
                        Circle()
                            .fill(.gray)
                            .stroke(.background, lineWidth: 1.5)
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(chosenDocks, id: \.station.stationID) { dock in
                    Annotation("\(dock.title) Dock", coordinate: dock.station.coordinate) {
                        DockBadge(title: dock.title, color: dock.color)
                            .accessibilityLabel("\(dock.title) dock, \(dock.station.name)")
                    }
                    .annotationTitles(.hidden)
                }
                if let center = pinCoordinate {
                    Annotation(pinLabel, coordinate: center, anchor: .bottom) {
                        pin(proxy)
                    }
                    .annotationTitles(.hidden)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                if isEditable {
                    MapScaleView()
                    MapCompass()
                }
            }
            .onTapGesture { point in
                guard isEditable, let tapped = proxy.convert(point, from: .local) else { return }
                move(to: tapped)
            }
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
                if position.positionedByUser { userMovedCameraAt = .now }
            }
            .overlay(alignment: .bottom) {
                if coordinate == nil {
                    Text("Search, use your location, or tap the map to drop a pin.")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
        }
        .allowsHitTesting(isEditable)
        .onChange(of: coordinateKey) { old, _ in
            guard let coordinate else { return }
            let isOwnMove = ownMove.map { $0.latitude == coordinate.latitude && $0.longitude == coordinate.longitude } ?? false
            // Fine-tuning by tap or drag leaves the camera alone unless the
            // circle no longer fits; a new search result is always framed.
            if isOwnMove && !old.isEmpty {
                fitIfOverflowing()
            } else {
                fit()
            }
        }
        .onChange(of: alertDistance) {
            // While sliding, the circle grows over the streets and the map
            // only zooms out when it would spill off; letting go frames it.
            if isSliding { fitIfOverflowing() } else { fit() }
        }
    }

    private func pin(_ proxy: MapProxy) -> some View {
        VStack(spacing: -5) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
        .shadow(radius: draggedCoordinate == nil ? 2 : 6, y: draggedCoordinate == nil ? 1 : 4)
        .scaleEffect(draggedCoordinate == nil ? 1 : 1.15, anchor: .bottom)
        .animation(.snappy, value: draggedCoordinate == nil)
        .highPriorityGesture(isEditable ? pinDrag(proxy) : nil)
        .accessibilityElement()
        .accessibilityLabel("Pin for \(pinLabel)")
        .accessibilityHint(isEditable ? "Drag to move it, or tap the map where it should go." : "")
        .accessibilityActions {
            if isEditable {
                Button("Move north") { nudge(north: 25) }
                Button("Move south") { nudge(north: -25) }
                Button("Move east") { nudge(east: 25) }
                Button("Move west") { nudge(east: -25) }
            }
        }
    }

    private func pinDrag(_ proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard let start = coordinate else { return }
                if dragOffset == nil, let tip = proxy.convert(start, to: .global) {
                    dragOffset = CGSize(width: tip.x - value.startLocation.x, height: tip.y - value.startLocation.y)
                }
                let offset = dragOffset ?? .zero
                let point = CGPoint(x: value.location.x + offset.width, y: value.location.y + offset.height)
                if let moved = proxy.convert(point, from: .global) {
                    draggedCoordinate = moved
                }
            }
            .onEnded { _ in
                if let draggedCoordinate { move(to: draggedCoordinate) }
                draggedCoordinate = nil
                dragOffset = nil
            }
    }

    private func move(to newCoordinate: CLLocationCoordinate2D) {
        ownMove = newCoordinate
        coordinate = newCoordinate
    }

    private func nudge(north: CLLocationDistance = 0, east: CLLocationDistance = 0) {
        guard let coordinate else { return }
        move(to: AlertMapGeometry.coordinate(coordinate, movedNorth: north, east: east))
    }

    /// Changes to this restart the camera logic; empty when there's no pin.
    private var coordinateKey: [Double] {
        coordinate.map { [$0.latitude, $0.longitude] } ?? []
    }

    // MARK: - Camera

    /// The rider panned or zoomed in the last moment, so leave the camera be.
    private var isPanning: Bool { Date.now.timeIntervalSince(userMovedCameraAt) < 0.6 }

    private func fit() {
        guard let coordinate, !isPanning else { return }
        withAnimation(.smooth) {
            position = .region(AlertMapGeometry.region(center: coordinate, radius: alertDistance))
        }
    }

    private func fitIfOverflowing() {
        guard let coordinate else { return }
        if let visibleRegion, AlertMapGeometry.circle(center: coordinate, radius: alertDistance, fitsIn: visibleRegion) { return }
        fit()
    }

    // MARK: - Stations

    /// Stations within the distance the dock search covers, as plain dots.
    /// Left off the small preview, where they'd bury the circle.
    private var nearbyStations: [StationInformation] {
        guard isEditable, let center = coordinate else { return [] }
        let chosen = [usualStationID, backupStationID]
        return AlertMapGeometry.stations(stations, within: StationNetwork.nearbyRadius, of: center)
            .filter { !chosen.contains($0.stationID) }
    }

    private var chosenDocks: [(title: String, color: Color, station: StationInformation)] {
        [("Usual", Color.green, usualStationID), ("Backup", Color.teal, backupStationID)].compactMap { title, color, id in
            guard let id, let station = stations.first(where: { $0.stationID == id }) else { return nil }
            return (title, color, station)
        }
    }

    // MARK: - Radius

    private var radiusControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Alert me within")
                Spacer()
                Text(Speech.length(alertDistance, width: .abbreviated))
                    .monospacedDigit()
                    .bold()
            }
            .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { alertDistance },
                    set: { alertDistance = SavedPlace.snappedAlertDistance($0) }
                ),
                in: SavedPlace.alertDistanceRange
            ) {
                Text("Alert radius")
            } minimumValueLabel: {
                Text(Speech.length(SavedPlace.alertDistanceRange.lowerBound, width: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(Speech.length(SavedPlace.alertDistanceRange.upperBound, width: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                isSliding = editing
                if !editing { fit() }
            }
            .accessibilityLabel("Alert radius")
            .accessibilityValue(Speech.length(alertDistance))
            .sensoryFeedback(.selection, trigger: alertDistance)
            Text("\(Speech.sentence(Speech.bikeTime(alertDistance))) from the pin")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The rider's usual or backup dock on the map.
private struct DockBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bicycle")
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color, in: .capsule)
        .overlay(Capsule().stroke(.background, lineWidth: 1.5))
        .fixedSize()
    }
}

/// The plain geometry behind the map's camera, kept apart so it can be tested.
nonisolated enum AlertMapGeometry {
    /// Meters per degree of latitude (and of longitude at the equator).
    static let metersPerDegree = 111_320.0
    /// How much room to leave around the circle when framing it.
    static let padding = 1.3

    /// A region that shows the whole circle with a little room around it.
    static func region(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> MKCoordinateRegion {
        let span = radius * 2 * padding
        return MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
    }

    /// True when the whole circle is inside `region`.
    static func circle(center: CLLocationCoordinate2D, radius: CLLocationDistance, fitsIn region: MKCoordinateRegion) -> Bool {
        let latitudeRadius = radius / metersPerDegree
        let longitudeRadius = radius / (metersPerDegree * cos(center.latitude * .pi / 180))
        return abs(center.latitude - region.center.latitude) + latitudeRadius <= region.span.latitudeDelta / 2
            && abs(center.longitude - region.center.longitude) + longitudeRadius <= region.span.longitudeDelta / 2
    }

    /// `coordinate` moved a few meters, for VoiceOver's "Move north" and friends.
    static func coordinate(_ coordinate: CLLocationCoordinate2D, movedNorth north: CLLocationDistance, east: CLLocationDistance) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coordinate.latitude + north / metersPerDegree,
            longitude: coordinate.longitude + east / (metersPerDegree * cos(coordinate.latitude * .pi / 180))
        )
    }

    /// The stations within `radius` of `center`. A cheap box check first,
    /// since this runs as the pin moves over ~2,000 stations.
    static func stations(_ stations: [StationInformation], within radius: CLLocationDistance, of center: CLLocationCoordinate2D) -> [StationInformation] {
        let latitudeRadius = radius / metersPerDegree
        let longitudeRadius = radius / (metersPerDegree * cos(center.latitude * .pi / 180))
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return stations.filter { station in
            abs(station.latitude - center.latitude) <= latitudeRadius
                && abs(station.longitude - center.longitude) <= longitudeRadius
                && here.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude)) <= radius
        }
    }
}

private extension StationInformation {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
