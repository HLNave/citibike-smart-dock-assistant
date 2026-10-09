//
//  FeatureViews.swift
//  Dock Finder
//
//  Dock near a place, station check, citywide status, and free-form asks.
//

import SwiftUI

struct PlaceSearchView: View {
    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var searchError: DockFinderError?
    @State private var model = AnswerModel()

    var body: some View {
        List {
            if model.phase != .idle {
                Section {
                    AnswerView(phase: model.phase)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if let searchError {
                Section {
                    ErrorCard(error: searchError)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if !results.isEmpty {
                Section("Places") {
                    ForEach(results, id: \.self) { result in
                        Button {
                            Task { await findDock(near: result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).foregroundStyle(.primary)
                                if let address = result.address {
                                    Text(address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .overlay {
            if results.isEmpty, searchError == nil, model.phase == .idle {
                ContentUnavailableView(
                    "Find a Dock Near a Place",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Search for an address, landmark or neighborhood, like Union Square.")
                )
            }
        }
        .navigationTitle("Dock Near a Place")
        .searchable(text: $query, prompt: "Union Square, 44 W 4th St…")
        .onSubmit(of: .search) { Task { await search() } }
    }

    private func search() async {
        model.reset()
        do {
            results = Array(try await MapKitPlaceSearch().search(query).prefix(8))
            searchError = nil
            // The best match is usually right, so answer for it straight away.
            if let first = results.first { await findDock(near: first) }
        } catch let error as DockFinderError {
            results = []
            searchError = error
        } catch {}
    }

    private func findDock(near destination: Destination) async {
        await model.run {
            try await DockFinderService.live.findDock(near: destination).answer
        }
    }
}

struct StationSearchView: View {
    @State private var query = ""
    @State private var directory: [StationInformation] = []
    @State private var loadError: DockFinderError?
    @State private var model = AnswerModel()

    var body: some View {
        List {
            if model.phase != .idle {
                Section {
                    AnswerView(phase: model.phase)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if let loadError {
                ErrorCard(error: loadError)
            } else if directory.isEmpty {
                ProgressView("Loading stations…")
            } else {
                Section(query.isEmpty ? "Stations" : "Matches") {
                    ForEach(matches, id: \.stationID) { station in
                        Button(station.name) {
                            Task {
                                await model.run {
                                    try await DockFinderService.live.checkStation(station.stationID).answer
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle("Check a Station")
        .searchable(text: $query, prompt: "Mercer and Bleecker")
        .task { await loadDirectory() }
    }

    private var matches: [StationInformation] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Array(directory.sorted { $0.name < $1.name }.prefix(50))
        }
        return directory
            .map { (station: $0, score: StationNameMatcher.score(name: $0.name, query: query)) }
            .filter { $0.score >= StationNameMatcher.threshold || $0.station.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.score > $1.score }
            .prefix(30)
            .map(\.station)
    }

    private func loadDirectory() async {
        guard directory.isEmpty else { return }
        do {
            directory = try await DockFinderService.live.stationDirectory()
            loadError = nil
        } catch let error as DockFinderError {
            loadError = error
        } catch {}
    }
}

struct CitywideView: View {
    @State private var model = AnswerModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AnswerView(phase: model.phase)
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Citywide Status")
        .task { await refresh() }
    }

    private func refresh() async {
        await model.run {
            try await DockFinderService.live.citywideSummary().answer
        }
    }
}

struct AskView: View {
    @State private var request = ""
    @State private var model = AnswerModel()
    @FocusState private var isFocused: Bool

    private let examples = [
        "Find me a dock near Union Square",
        "Is Mercer and Bleecker full?",
        "School",
        "Check my school dock",
        "How many bikes are out?",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Ask anything about docks…", text: $request, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await ask() } }

                Button {
                    Task { await ask() }
                } label: {
                    Label("Ask", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)

                AnswerView(phase: model.phase)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Try")
                        .font(.subheadline.weight(.semibold))
                    ForEach(examples, id: \.self) { example in
                        Button("“\(example)”") {
                            request = example
                            Task { await ask() }
                        }
                        .font(.subheadline)
                    }
                }

                Text(routingNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Ask Dock Finder")
    }

    private var routingNote: String {
        let server = N8NAssistantClient.configured() == nil
            ? "No Dock Finder server is set up in this build, so anything else gets a short help message."
            : "Anything else is sent to the Dock Finder server."
        let model = OnDeviceModelParser.isAvailable
            ? " Apple Intelligence on this iPhone helps understand other wording."
            : ""
        return "Requests for a dock near you, a place or a saved place, a station check, or citywide totals are answered on this iPhone.\(model) \(server)"
    }

    private func ask() async {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFocused = false
        await model.run(needsLocation: true) {
            try await AssistantRouter.live().answer(text)
        }
    }
}
