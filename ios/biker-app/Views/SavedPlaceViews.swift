//
//  SavedPlaceViews.swift
//  Dock Finder
//
//  Saved places: checking one, choosing its usual and backup docks, adding,
//  editing (name, nicknames, and the pin and alert radius on a map), and
//  reordering.
//

import CoreLocation
import SwiftUI

struct SavedPlaceView: View {
    let placeID: UUID

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss
    @State private var model = AnswerModel()
    @State private var rideModel = AnswerModel()
    @State private var confirmsDelete = false
    @State private var showsEdit = false
    @State private var showsAlertEditor = false
    /// Docks that are no longer in Citi Bike's station list.
    @State private var missingDocks: [String] = []
    /// Warnings for docks past the distance the dock search covers.
    @State private var distantDocks: [String] = []
    /// Every station, for the map.
    @State private var stations: [StationInformation] = []

    var body: some View {
        if let place = savedPlaces.place(id: placeID) {
            List {
                Section {
                    AnswerView(phase: model.phase)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Button {
                        Task { await check(place) }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }

                Section {
                    NavigationLink {
                        DockPicker(place: place, slot: .usual)
                    } label: {
                        LabeledContent("Usual Dock", value: place.usualStationName ?? "None")
                    }
                    NavigationLink {
                        DockPicker(place: place, slot: .backup)
                    } label: {
                        LabeledContent("Backup Dock", value: place.backupStationName ?? "None")
                    }
                    .disabled(place.usualStationID == nil)
                    ForEach(missingDocks, id: \.self) { name in
                        Label("\(name) is no longer in Citi Bike's station list. Pick a new dock.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ForEach(distantDocks, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    InfoHeader("Docks", message: "Dock Finder checks your usual dock first, then your backup, and only then suggests the nearest other station with room.")
                }

                Section {
                    Button {
                        showsAlertEditor = true
                    } label: {
                        PlaceAlertMap(
                            coordinate: .constant(place.location.coordinate),
                            alertDistance: .constant(place.alertDistance),
                            pinLabel: place.name,
                            stations: stations,
                            usualStationID: place.usualStationID,
                            backupStationID: place.backupStationID,
                            isEditable: false
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Map of \(place.name) with its alert radius, \(Speech.length(place.alertDistance))")
                    .accessibilityHint("Opens the map to move the pin or change the radius.")
                    if let address = place.address {
                        LabeledContent("Address", value: address)
                    }
                    if !place.aliases.isEmpty {
                        LabeledContent("Also Called", value: place.aliases.joined(separator: ", "))
                    }
                    Button {
                        showsAlertEditor = true
                    } label: {
                        LabeledContent("Alert Radius", value: Speech.length(place.alertDistance))
                    }
                    .tint(.primary)
                } footer: {
                    Text("On a ride here, or arriving with Alert Me When I Arrive on, Dock Finder tells you where to dock as you bike into the circle. Tap the map to move the pin or change the radius.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { place.arrivalAlerts },
                        set: { enabled in
                            var updated = place
                            updated.arrivalAlerts = enabled
                            savedPlaces.update(updated)
                        }
                    )) {
                        InfoLabel(
                            "Alert Me When I Arrive",
                            message: "When you bike within \(Speech.length(place.alertDistance)) of \(place.name), Dock Finder tells you where to dock, even if you didn't start a ride. Needs location access set to Always; walking and the subway are skipped when Motion & Fitness is allowed."
                        )
                    }
                }

                Section {
                    Button {
                        Task {
                            await rideModel.run(needsLocation: true) {
                                try await AssistantRouter.live().handle(.startRide(place.name))
                            }
                        }
                    } label: {
                        Label("Start a Ride Here", systemImage: "figure.outdoor.cycle")
                    }
                    .disabled(rideModel.isLoading)
                    AnswerView(phase: rideModel.phase)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Siri")
                } footer: {
                    Text("“Hey Siri, ask Dock Finder to start a ride to \(place.name.lowercased()).” You'll hear where to dock as you get close.")
                }

                Section {
                    Button("Delete Place", role: .destructive) {
                        confirmsDelete = true
                    }
                }
            }
            .navigationTitle(place.name)
            .toolbar {
                Button("Edit") { showsEdit = true }
            }
            .sheet(isPresented: $showsEdit) {
                EditPlaceView(place: place)
            }
            .sheet(isPresented: $showsAlertEditor) {
                PlaceAlertEditor(place: place)
            }
            .task(id: place) {
                await check(place)
                await findMissingDocks(place)
            }
            .confirmationDialog("Delete \(place.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    savedPlaces.remove(id: placeID)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Place Deleted", systemImage: "star.slash")
        }
    }

    private func check(_ place: SavedPlace) async {
        await model.run {
            try await DockFinderService.live.findDock(for: place).answer
        }
    }

    private func findMissingDocks(_ place: SavedPlace) async {
        guard let directory = try? await DockFinderService.live.stationDirectory() else { return }
        stations = directory
        distantDocks = place.distantDocks(from: place.location, in: directory).map { dock in
            "\(dock.name) is \(Speech.length(dock.distance)) from \(place.name). Pick a closer dock."
        }
        let known = Set(directory.map(\.stationID))
        missingDocks = [
            (place.usualStationID, place.usualStationName),
            (place.backupStationID, place.backupStationName),
        ].compactMap { id, name in
            guard let id, !known.contains(id) else { return nil }
            return name ?? "A dock you picked"
        }
    }
}

/// Stations near a saved place, nearest first.
struct DockPicker: View {
    enum Slot { case usual, backup }

    let place: SavedPlace
    let slot: Slot

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss
    @State private var stations: [StationOption] = []
    @State private var error: DockFinderError?

    struct StationOption: Identifiable {
        let id: String
        let name: String
        let distance: Double
    }

    private var selectedID: String? {
        slot == .usual ? place.usualStationID : place.backupStationID
    }

    /// The other slot's station, which can't be picked here.
    private var excludedID: String? {
        slot == .usual ? nil : place.usualStationID
    }

    var body: some View {
        List {
            Section {
                Button {
                    choose(nil)
                } label: {
                    pickerRow(title: "None", subtitle: nil, selected: selectedID == nil)
                }
                .tint(.primary)
            }
            Section("Stations within 1.2 km") {
                if let error {
                    ErrorCard(error: error)
                } else if stations.isEmpty {
                    ProgressView()
                }
                ForEach(stations.filter { $0.id != excludedID }) { station in
                    Button {
                        choose(station)
                    } label: {
                        pickerRow(
                            title: station.name,
                            subtitle: Speech.distance(station.distance, from: place.name),
                            selected: station.id == selectedID
                        )
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle(slot == .usual ? "Usual Dock" : "Backup Dock")
        .task { await loadStations() }
    }

    private func pickerRow(title: String, subtitle: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(.rect)
    }

    private func choose(_ station: StationOption?) {
        switch slot {
        case .usual:
            savedPlaces.setUsualDock(stationID: station?.id, stationName: station?.name, for: place.id)
            if station == nil {
                // A backup without a usual dock would never be used.
                savedPlaces.setBackupDock(stationID: nil, stationName: nil, for: place.id)
            }
        case .backup:
            savedPlaces.setBackupDock(stationID: station?.id, stationName: station?.name, for: place.id)
        }
        dismiss()
    }

    private func loadStations() async {
        do {
            let center = place.location
            stations = try await DockFinderService.live.stationDirectory()
                .map { StationOption(id: $0.stationID, name: $0.name, distance: center.distance(from: .init(latitude: $0.latitude, longitude: $0.longitude))) }
                .filter { $0.distance <= StationNetwork.nearbyRadius }
                .sorted { $0.distance < $1.distance }
            error = nil
        } catch let failure as DockFinderError {
            error = failure
        } catch {}
    }
}

/// Sets a place's location and alert radius: search or use where you're
/// standing to drop the pin, then drag it or tap the map to fine-tune, and
/// slide to size the circle.
struct PlaceLocationPicker: View {
    /// What a moved pin is called until its address is found.
    static let droppedPinName = "Dropped Pin"

    @Binding var selected: Destination?
    @Binding var alertDistance: CLLocationDistance
    /// The place being edited, for its usual and backup docks. Nil when adding.
    var place: SavedPlace? = nil

    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var searchError: DockFinderError?
    @State private var isWorking = false
    @State private var stations: [StationInformation] = []
    /// Set when the chosen spot has no Citi Bike station nearby.
    @State private var nearestStation: CLLocationDistance?
    /// The usual or backup dock is past the distance the dock search covers.
    @State private var distantDocks: [(name: String, distance: CLLocationDistance)] = []
    /// Bumped each time the pin is moved on the map, restarting the address lookup.
    @State private var pinMoves = 0
    @State private var isFindingAddress = false

    var body: some View {
        Section {
            PlaceAlertMap(
                coordinate: pin,
                alertDistance: $alertDistance,
                pinLabel: selected?.name ?? "New place",
                stations: stations,
                usualStationID: place?.usualStationID,
                backupStationID: place?.backupStationID
            )
            .listRowInsets(EdgeInsets())
            if let selected {
                VStack(alignment: .leading, spacing: 2) {
                    Label(isFindingAddress ? "Finding the address…" : selected.name, systemImage: "mappin.circle.fill")
                    if let address = selected.address, address != selected.name {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let nearestStation, nearestStation > StationNetwork.nearbyRadius {
                    Label("The nearest Citi Bike station is \(Speech.length(nearestStation)) away, so Dock Finder won't find docks here.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                ForEach(distantDocks, id: \.name) { dock in
                    Label("\(dock.name) is \(Speech.length(dock.distance)) from here. Pick a closer dock after you save.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            HStack {
                TextField("Address or place, e.g. NYU Stern", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if isWorking {
                    ProgressView()
                } else {
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Button {
                Task { await useCurrentLocation() }
            } label: {
                Label("Use My Current Location", systemImage: "location.fill")
            }
            .disabled(isWorking)
            if let searchError {
                Text(searchError.localizedStringResource)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.self) { result in
                Button {
                    choose(result)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).foregroundStyle(.primary)
                            if let address = result.address {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if result == selected {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Where is it?")
        } footer: {
            Text("Search or use your current location, then drag the pin or tap the map to put it exactly where you're going. On a ride here, or arriving with Alert Me When I Arrive on, Dock Finder tells you where to dock as you bike into the circle. Bigger gives you more time to change course.")
        }
        .task(id: selected) { await checkDistances() }
        .task(id: pinMoves) { await lookUpAddress() }
    }

    /// The pin on the map. Moving it drops a new, unnamed spot there.
    private var pin: Binding<CLLocationCoordinate2D?> {
        Binding(
            get: { selected?.location.coordinate },
            set: { coordinate in
                guard let coordinate else { return }
                selected = Destination(name: Self.droppedPinName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                pinMoves += 1
            }
        )
    }

    private func choose(_ destination: Destination) {
        isFindingAddress = false
        selected = destination
    }

    private func search() async {
        isWorking = true
        defer { isWorking = false }
        do {
            results = Array(try await MapKitPlaceSearch().search(query).prefix(6))
            if let first = results.first { choose(first) }
            searchError = nil
        } catch let error as DockFinderError {
            results = []
            searchError = error
        } catch {}
    }

    private func useCurrentLocation() async {
        isWorking = true
        defer { isWorking = false }
        if LocationService.shared.authorizationStatus == .notDetermined {
            _ = await LocationService.shared.requestWhenInUseAuthorization()
        }
        do {
            let here = try await LocationService.shared.currentLocation().location
            let address = await MapKitPlaceSearch().address(for: here)
            results = []
            searchError = nil
            choose(Destination(
                name: address ?? "Current Location",
                latitude: here.coordinate.latitude,
                longitude: here.coordinate.longitude,
                address: address
            ))
        } catch let error as DockFinderError {
            searchError = error
        } catch {}
    }

    /// Looks up the street address of a pin moved on the map. Waits for the
    /// pin to settle first, so dropping it a few times in a row (or a drag)
    /// is one lookup rather than one per move.
    private func lookUpAddress() async {
        guard pinMoves > 0, let pinned = selected else { return }
        isFindingAddress = true
        try? await Task.sleep(for: .milliseconds(600))
        // A newer move restarted this task and will finish the job.
        guard !Task.isCancelled else { return }
        let address = await MapKitPlaceSearch().address(for: pinned.location)
        guard !Task.isCancelled else { return }
        isFindingAddress = false
        // Unless the rider searched or picked another spot meanwhile.
        guard selected == pinned else { return }
        selected = Destination(
            name: address ?? Self.droppedPinName,
            latitude: pinned.latitude,
            longitude: pinned.longitude,
            address: address
        )
    }

    private func checkDistances() async {
        if stations.isEmpty {
            stations = (try? await DockFinderService.live.stationDirectory()) ?? []
        }
        guard let selected, !stations.isEmpty else {
            nearestStation = nil
            distantDocks = []
            return
        }
        nearestStation = MapKitPlaceSearch.distanceToNearestStation(from: selected.location, in: stations)
        distantDocks = place?.distantDocks(from: selected.location, in: stations) ?? []
    }
}

/// Name and nicknames, shared by Add and Edit.
private struct PlaceDetailsSections: View {
    @Binding var name: String
    @Binding var aliases: [String]
    let validationError: SavedPlacesStore.ValidationError?

    @State private var newAlias = ""
    private let suggestions = ["School", "Work", "Home", "Gym"]

    var body: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
                            .buttonStyle(.bordered)
                            .tint(name == suggestion ? .accentColor : .secondary)
                    }
                }
            }
            if let validationError {
                Text(validationError.localizedStringResource)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("What do you call it?")
        } footer: {
            Text("Then say, for example, “Hey Siri, ask Dock Finder to start a ride to \(name.isEmpty ? "school" : name.lowercased()).”")
        }

        Section {
            ForEach(aliases, id: \.self) { alias in
                Text(alias)
            }
            .onDelete { aliases.remove(atOffsets: $0) }
            HStack {
                TextField("Add another name, e.g. Stern", text: $newAlias)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addAlias)
                Button("Add", action: addAlias)
                    .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Other Names")
        } footer: {
            Text("Optional. Siri will recognize these too.")
        }
    }

    private func addAlias() {
        let alias = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty, !aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) else { return }
        aliases.append(alias)
        newAlias = ""
    }
}

struct AddPlaceView: View {
    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var aliases: [String] = []
    @State private var alertDistance = SavedPlace.defaultAlertDistance
    @State private var selected: Destination?

    var body: some View {
        NavigationStack {
            Form {
                PlaceDetailsSections(name: $name, aliases: $aliases, validationError: validationError)
                PlaceLocationPicker(selected: $selected, alertDistance: $alertDistance)
            }
            .navigationTitle("Add a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.isEmpty || validationError != nil || selected == nil)
                }
            }
        }
    }

    private var validationError: SavedPlacesStore.ValidationError? {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : savedPlaces.validate(name: name, aliases: aliases)
    }

    private func save() {
        guard let selected, savedPlaces.validate(name: name, aliases: aliases) == nil else { return }
        savedPlaces.add(SavedPlace(
            name: name,
            aliases: aliases,
            latitude: selected.latitude,
            longitude: selected.longitude,
            address: selected.address ?? selected.name,
            alertDistance: alertDistance
        ))
        dismiss()
    }
}

struct EditPlaceView: View {
    let place: SavedPlace

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var aliases: [String]
    @State private var alertDistance: CLLocationDistance
    @State private var selected: Destination?

    init(place: SavedPlace) {
        self.place = place
        _name = State(initialValue: place.name)
        _aliases = State(initialValue: place.aliases)
        _alertDistance = State(initialValue: place.alertDistance)
        _selected = State(initialValue: place.pickedLocation)
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceDetailsSections(name: $name, aliases: $aliases, validationError: validationError)
                PlaceLocationPicker(selected: $selected, alertDistance: $alertDistance, place: place)
            }
            .navigationTitle("Edit \(place.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(validationError != nil || selected == nil)
                }
            }
        }
    }

    private var validationError: SavedPlacesStore.ValidationError? {
        savedPlaces.validate(name: name, aliases: aliases, excluding: place.id)
    }

    private func save() {
        guard let selected, validationError == nil else { return }
        // Start from the stored place, so a dock picked meanwhile isn't undone.
        var updated = (savedPlaces.place(id: place.id) ?? place).relocated(to: selected, alertDistance: alertDistance)
        updated.name = name
        updated.aliases = aliases
        savedPlaces.update(updated)
        dismiss()
    }
}

/// The place's pin and alert radius on their own, opened from its map.
struct PlaceAlertEditor: View {
    let place: SavedPlace

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss

    @State private var alertDistance: CLLocationDistance
    @State private var selected: Destination?

    init(place: SavedPlace) {
        self.place = place
        _alertDistance = State(initialValue: place.alertDistance)
        _selected = State(initialValue: place.pickedLocation)
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceLocationPicker(selected: $selected, alertDistance: $alertDistance, place: place)
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(selected == nil)
                }
            }
        }
    }

    private func save() {
        guard let selected, let current = savedPlaces.place(id: place.id) else { return }
        savedPlaces.update(current.relocated(to: selected, alertDistance: alertDistance))
        dismiss()
    }
}

private extension SavedPlace {
    /// Where the location picker starts when editing this place.
    var pickedLocation: Destination {
        Destination(name: address ?? name, latitude: latitude, longitude: longitude, address: address)
    }
}

/// Reorder or delete saved places.
struct ManagePlacesView: View {
    @Environment(SavedPlacesStore.self) private var savedPlaces

    var body: some View {
        List {
            ForEach(savedPlaces.places) { place in
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                    if let address = place.address {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { savedPlaces.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { savedPlaces.remove(atOffsets: $0) }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Saved Places")
    }
}
