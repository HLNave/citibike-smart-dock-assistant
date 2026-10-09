//
//  SavedPlaceViews.swift
//  Dock Finder
//
//  Adding a saved place, checking it, and choosing its usual dock.
//

import CoreLocation
import SwiftUI

struct SavedPlaceView: View {
    let placeID: UUID

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss
    @State private var model = AnswerModel()
    @State private var confirmsDelete = false

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
                    if let address = place.address {
                        LabeledContent("Address", value: address)
                    }
                    NavigationLink {
                        UsualDockPicker(place: place)
                    } label: {
                        LabeledContent("Usual Dock", value: place.usualStationName ?? "None")
                    }
                } footer: {
                    Text("With a usual dock set, Dock Finder checks it first and only suggests another station when it's full, almost full, or closed.")
                }

                Section {
                    Text("“Hey Siri, find a dock near \(place.name.lowercased()) with Dock Finder.”")
                } header: {
                    Text("Siri")
                } footer: {
                    Text("For a heads-up before you arrive, create an Arrive automation in the Shortcuts app that runs “Find Dock Near Saved Place” for \(place.name), then Speak Text. See the README for steps.")
                }

                Section {
                    Button("Delete Place", role: .destructive) {
                        confirmsDelete = true
                    }
                }
            }
            .navigationTitle(place.name)
            .task(id: place) { await check(place) }
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
            try await DockFinderService.live
                .findDock(near: place.destination, usualStationID: place.usualStationID)
                .answer
        }
    }
}

/// Stations near a saved place, nearest first.
struct UsualDockPicker: View {
    let place: SavedPlace

    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss
    @State private var stations: [StationOption] = []
    @State private var error: DockFinderError?

    struct StationOption: Identifiable {
        let id: String
        let name: String
        let distance: Double
    }

    var body: some View {
        List {
            Section {
                Button {
                    choose(nil)
                } label: {
                    pickerRow(title: "None", subtitle: nil, selected: place.usualStationID == nil)
                }
                .tint(.primary)
            }
            Section("Stations within 1.2 km") {
                if let error {
                    ErrorCard(error: error)
                } else if stations.isEmpty {
                    ProgressView()
                }
                ForEach(stations) { station in
                    Button {
                        choose(station)
                    } label: {
                        pickerRow(
                            title: station.name,
                            subtitle: Speech.distance(station.distance, from: place.name),
                            selected: station.id == place.usualStationID
                        )
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("Usual Dock")
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
        savedPlaces.setUsualDock(stationID: station?.id, stationName: station?.name, for: place.id)
        dismiss()
    }

    private func loadStations() async {
        do {
            let center = place.destination.location
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

struct AddPlaceView: View {
    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var selected: Destination?
    @State private var searchError: DockFinderError?
    @State private var isSearching = false

    private let suggestions = ["School", "Work", "Home", "Gym"]

    var body: some View {
        NavigationStack {
            Form {
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
                } header: {
                    Text("What do you call it?")
                } footer: {
                    Text("This is the name you'll say to Siri: “find a dock near \(name.isEmpty ? "school" : name.lowercased())”.")
                }

                Section("Where is it?") {
                    HStack {
                        TextField("Address or place, e.g. NYU Stern", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if isSearching {
                            ProgressView()
                        } else {
                            Button("Search") { Task { await search() } }
                                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let searchError {
                        Text(searchError.localizedStringResource)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { result in
                        Button {
                            selected = result
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
                }
            }
            .navigationTitle("Add a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || selected == nil)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = Array(try await MapKitPlaceSearch().search(query).prefix(6))
            selected = results.first
            searchError = nil
        } catch let error as DockFinderError {
            results = []
            selected = nil
            searchError = error
        } catch {}
    }

    private func save() {
        guard let selected else { return }
        savedPlaces.add(SavedPlace(
            name: trimmedName,
            latitude: selected.latitude,
            longitude: selected.longitude,
            address: selected.address ?? selected.name
        ))
        dismiss()
    }
}
