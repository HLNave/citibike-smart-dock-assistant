//
//  PlaceAlertMap.swift
//  Dock Finder
//
//  A saved place on a map: its pin, which the rider can press and drag or
//  drop with a tap, and its alert radius drawn to scale as a circle, with
//  a slider to change it. Nearby Citi Bike stations show as dots, with the
//  usual and backup docks labeled. The place's screen shows a smaller,
//  read-only copy with just the pin, circle and docks.
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
    /// Set while the rider holds the pin, which also stops the map from
    /// panning so the two don't fight over the finger. The place only moves
    /// (and its address is looked up) when the pin is let go. Gesture state,
    /// so it clears itself if iOS cancels the touch.
    @GestureState private var pinHold: PinHold?
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

    /// How long the rider holds the pin before it lifts and can be dragged.
    /// Moving sooner pans the map instead, so a drag is never both.
    static let pinHoldDuration = 0.2

    private struct PinHold {
        /// Where the pin is being dragged; nil until the finger moves.
        var coordinate: CLLocationCoordinate2D?
    }

    private var pinCoordinate: CLLocationCoordinate2D? { pinHold?.coordinate ?? coordinate }

    private var interactionModes: MapInteractionModes {
        isEditable && pinHold == nil ? [.pan, .zoom, .rotate] : []
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: interactionModes) {
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
                guard isEditable else { return }
                // A tap on the pin itself reaches the map too; it isn't a
                // new spot, and moving there would walk the pin north.
                if let coordinate, let tip = proxy.convert(coordinate, to: .local),
                   AlertMapGeometry.pinHitArea(tip: tip).contains(point) { return }
                guard let tapped = proxy.convert(point, from: .local) else { return }
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
            reframe(after: old.isEmpty ? .firstPin : isOwnMove ? .pinMoved : .placeChanged)
        }
        .onChange(of: alertDistance) {
            reframe(after: isSliding ? .radiusChanging : .radiusSet)
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
        .frame(width: AlertMapGeometry.pinSize.width, height: AlertMapGeometry.pinSize.height, alignment: .bottom)
        .contentShape(.rect)
        .shadow(radius: pinHold == nil ? 2 : 6, y: pinHold == nil ? 1 : 4)
        .scaleEffect(pinHold == nil ? 1 : 1.15, anchor: .bottom)
        .animation(.snappy, value: pinHold == nil)
        .sensoryFeedback(trigger: pinHold == nil) { _, released in released ? nil : .impact(weight: .medium) }
        // Its own tap, so a tap on the pin is never taken as one on the map.
        .onTapGesture {}
        .highPriorityGesture(isEditable ? pinGesture(proxy) : nil)
        .accessibilityElement()
        .accessibilityLabel("Pin for \(pinLabel)")
        .accessibilityHint(isEditable ? "Touch and hold, then drag to move it, or tap the map where it should go." : "")
        .accessibilityActions {
            if isEditable {
                Button("Move north") { nudge(north: 25) }
                Button("Move south") { nudge(north: -25) }
                Button("Move east") { nudge(east: 25) }
                Button("Move west") { nudge(east: -25) }
            }
        }
    }

    /// Touch and hold, then drag. MapKit's own pan isn't a SwiftUI gesture,
    /// so no gesture priority can stop it; instead a quick move pans the
    /// map (the press fails), and once the pin lifts the map's panning and
    /// zooming are switched off until it's let go.
    private func pinGesture(_ proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: Self.pinHoldDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($pinHold) { value, hold, _ in
                guard case .second(true, let drag) = value else { return }
                hold = PinHold(coordinate: drag.flatMap { draggedCoordinate($0, proxy) } ?? hold?.coordinate)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      AlertMapGeometry.isDrag(drag.translation),
                      let moved = draggedCoordinate(drag, proxy)
                else { return }
                move(to: moved)
            }
    }

    /// Where the pin's tip is under a drag, keeping the gap between finger
    /// and tip so the pin doesn't jump. The map can't move during the drag,
    /// so the tip's starting point is still where the place is now.
    private func draggedCoordinate(_ drag: DragGesture.Value, _ proxy: MapProxy) -> CLLocationCoordinate2D? {
        guard let coordinate, let tip = proxy.convert(coordinate, to: .global) else { return nil }
        return proxy.convert(AlertMapGeometry.draggedTip(tip, from: drag.startLocation, to: drag.location), from: .global)
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

    private func reframe(after change: AlertMapCamera.Change) {
        guard let coordinate else { return }
        let fits = visibleRegion.map { AlertMapGeometry.circle(center: coordinate, radius: alertDistance, fitsIn: $0) } ?? false
        let riderMovedMap = Date.now.timeIntervalSince(userMovedCameraAt) < AlertMapCamera.recentMoveInterval
        guard AlertMapCamera.shouldReframe(after: change, circleFits: fits, riderMovedMapRecently: riderMovedMap) else { return }
        fit()
    }

    private func fit() {
        guard let coordinate else { return }
        withAnimation(.smooth) {
            position = .region(AlertMapGeometry.region(center: coordinate, radius: alertDistance))
        }
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
            // No `step:`, which on iOS 26 draws a tick for each of the 27
            // steps. Without one, VoiceOver would move it by a tenth of the
            // range and the snapping would round that off unevenly, so it
            // gets its own element that steps by 50 m.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Alert radius")
            .accessibilityValue(Speech.length(alertDistance))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: alertDistance = SavedPlace.steppedAlertDistance(alertDistance, by: 1)
                case .decrement: alertDistance = SavedPlace.steppedAlertDistance(alertDistance, by: -1)
                @unknown default: break
                }
            }
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

/// When the editor moves the camera to show the whole circle.
nonisolated enum AlertMapCamera {
    enum Change {
        /// The place got its first spot.
        case firstPin
        /// The rider tapped, dragged or nudged the pin.
        case pinMoved
        /// A search result or "Use My Current Location" moved the place.
        case placeChanged
        /// The slider is moving.
        case radiusChanging
        /// The radius settled: the slider was let go, or VoiceOver adjusted it.
        case radiusSet
    }

    /// How long after the rider pans or zooms the map counts as theirs.
    static let recentMoveInterval: TimeInterval = 0.6

    /// Fine-tuning (a pin moved by the rider, a sliding radius) only moves
    /// the camera when the circle no longer fits, even right after a pan,
    /// so a circle pushed off-screen always comes back. A new place found
    /// some other way is framed, unless the rider just moved the map and it
    /// already shows the whole circle.
    static func shouldReframe(after change: Change, circleFits: Bool, riderMovedMapRecently: Bool) -> Bool {
        switch change {
        case .firstPin, .radiusSet: true
        case .pinMoved, .radiusChanging: !circleFits
        case .placeChanged: !(circleFits && riderMovedMapRecently)
        }
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

    /// The pin's frame, with its tip at the bottom center.
    static let pinSize = CGSize(width: 44, height: 52)
    /// Extra room around the pin that still counts as touching it.
    static let pinTouchSlop: CGFloat = 8

    /// Where a touch counts as on the pin whose tip is at `tip`.
    static func pinHitArea(tip: CGPoint) -> CGRect {
        CGRect(
            x: tip.x - pinSize.width / 2,
            y: tip.y - pinSize.height,
            width: pinSize.width,
            height: pinSize.height
        ).insetBy(dx: -pinTouchSlop, dy: -pinTouchSlop)
    }

    /// The pin's tip after a drag from `start` to `location`: it moves with
    /// the finger, keeping the gap it started with.
    static func draggedTip(_ tip: CGPoint, from start: CGPoint, to location: CGPoint) -> CGPoint {
        CGPoint(x: tip.x + location.x - start.x, y: tip.y + location.y - start.y)
    }

    /// A press that barely moved isn't a drag, so holding and letting go
    /// leaves the place (and its address) alone.
    static func isDrag(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= 3
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
