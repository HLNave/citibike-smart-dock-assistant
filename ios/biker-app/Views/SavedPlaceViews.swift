//
//  SavedPlaceViews.swift
//  Dock Finder
//
//  Saved places: checking one, choosing its usual and backup docks, adding,
//  editing (name, nicknames, location, alert distance), and reordering.
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
    /// Docks that are no longer in Citi Bike's station list.
    @State private var missingDocks: [String] = []

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
                } header: {
                    Text("Docks")
                } footer: {
                    Text("Dock Finder checks your usual dock first, then your backup, and only then suggests the nearest other station with room.")
                }

                Section {
                    if let address = place.address {
                        LabeledContent("Address", value: address)
                    }
                    if !place.aliases.isEmpty {
                        LabeledContent("Also Called", value: place.aliases.joined(separator: ", "))
                    }
                    LabeledContent("Ride Alert", value: "\(Speech.length(place.alertDistance)) out")
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
                    Text("“Hey Siri, ask Dock Finder.” Then say “\(place.name.lowercased())” for a dock now, or “start a ride to \(place.name.lowercased())” to hear where to dock as you get close.")
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

/// Search, or use where you're standing, to set a place's location.
struct PlaceLocationPicker: View {
    @Binding var selected: Destination?

    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var searchError: DockFinderError?
    @State private var isWorking = false
    /// Set when the chosen spot has no Citi Bike station nearby.
    @State private var nearestStation: CLLocationDistance?

    var body: some View {
        Section {
            if let selected {
                VStack(alignment: .leading, spacing: 2) {
                    Label(selected.name, systemImage: "mappin.circle.fill")
                    if let address = selected.address, address != selected.name {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let nearestStation, nearestStation > StationNetwork.nearbyRadius {
                    Label("The nearest Citi Bike station is \(Speech.length(nearestStation)) away, so Dock Finder won't find docks here.", systemImage: "exclamationmark.triangle.fill")
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
        }
        .task(id: selected) { await checkServiceArea() }
    }

    private func choose(_ destination: Destination) {
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

    private func checkServiceArea() async {
        guard let selected,
              let directory = try? await DockFinderService.live.stationDirectory()
        else {
            nearestStation = nil
            return
        }
        nearestStation = MapKitPlaceSearch.distanceToNearestStation(from: selected.location, in: directory)
    }
}

/// Name, nicknames and alert distance, shared by Add and Edit.
private struct PlaceDetailsSections: View {
    @Binding var name: String
    @Binding var aliases: [String]
    @Binding var alertDistance: CLLocationDistance
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
            Text("When Siri asks where you're headed, say “\(name.isEmpty ? "school" : name.lowercased())”.")
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

        Section {
            Picker("Alert me", selection: $alertDistance) {
                ForEach(SavedPlace.alertDistanceOptions, id: \.self) { distance in
                    Text("\(Speech.length(distance)) out").tag(distance)
                }
            }
        } header: {
            Text("Rides")
        } footer: {
            Text("On a ride here, Dock Finder tells you where to dock once you're this close. Farther gives you more time to change course.")
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
                PlaceDetailsSections(name: $name, aliases: $aliases, alertDistance: $alertDistance, validationError: validationError)
                PlaceLocationPicker(selected: $selected)
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
        _selected = State(initialValue: Destination(
            name: place.address ?? place.name,
            latitude: place.latitude,
            longitude: place.longitude,
            address: place.address
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceDetailsSections(name: $name, aliases: $aliases, alertDistance: $alertDistance, validationError: validationError)
                PlaceLocationPicker(selected: $selected)
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
        var updated = place
        updated.name = name
        updated.aliases = aliases
        updated.alertDistance = alertDistance
        let moved = selected.latitude != place.latitude || selected.longitude != place.longitude
        if moved {
            updated.latitude = selected.latitude
            updated.longitude = selected.longitude
            updated.address = selected.address ?? selected.name
        }
        savedPlaces.update(updated)
        dismiss()
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
