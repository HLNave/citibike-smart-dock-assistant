//
//  RideViews.swift
//  Dock Finder
//
//  The home screen's ride card, the Start Ride sheet, and the notice that
//  asks for Always location access.
//

import CoreLocation
import SwiftUI

/// Shows the active ride, or the last arrival answer, on the home screen.
struct RideCard: View {
    @Environment(RideTracker.self) private var rides
    @State private var showsStartRide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ride = rides.currentRide {
                activeRide(ride)
            } else {
                if let arrival = rides.lastArrival {
                    lastArrival(arrival)
                }
                Button {
                    showsStartRide = true
                } label: {
                    Label("Start a Ride", systemImage: "figure.outdoor.cycle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $showsStartRide) {
            StartRideView()
        }
    }

    private func activeRide(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Riding to \(ride.destination.name)", systemImage: "figure.outdoor.cycle")
                .font(.headline)
            Text(rideDetails(ride))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AlwaysLocationNotice()
            Button(role: .destructive) {
                Task { await rides.end() }
            } label: {
                Label("End Ride", systemImage: "xmark.circle")
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private func rideDetails(_ ride: Ride) -> String {
        var parts = ["You'll hear where to dock about \(Speech.length(ride.alertDistance)) out."]
        if let remaining = rides.distanceRemaining {
            parts.append("\(Speech.length(remaining)) to go.")
        }
        parts.append("Stops watching at \(ride.expiresAt.formatted(date: .omitted, time: .shortened)).")
        return parts.joined(separator: " ")
    }

    private func lastArrival(_ arrival: RideArrival) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Arrived near \(arrival.destination)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    rides.dismissLastArrival()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            AnswerCard(answer: arrival.answer)
        }
    }
}

/// Explains, and asks for, the Always access rides need with the phone locked.
struct AlwaysLocationNotice: View {
    private static let askedKey = "askedForAlwaysLocation"

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var status = LocationService.shared.authorizationStatus

    var body: some View {
        Group {
            if status != .authorizedAlways {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Rides need Always location access to alert you with your phone locked.", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(buttonTitle, action: requestAccess)
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = LocationService.shared.authorizationStatus }
        }
    }

    /// iOS only shows the upgrade prompt once; after that, Settings is the only way.
    private var canPrompt: Bool {
        status == .authorizedWhenInUse && !UserDefaults.standard.bool(forKey: Self.askedKey)
            || status == .notDetermined
    }

    private var buttonTitle: LocalizedStringKey {
        canPrompt ? "Allow Always" : "Open Settings"
    }

    private func requestAccess() {
        if canPrompt {
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            Task {
                if status == .notDetermined {
                    _ = await LocationService.shared.requestWhenInUseAuthorization()
                }
                LocationService.shared.requestAlwaysAuthorization()
                status = LocationService.shared.authorizationStatus
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// Pick a saved place or search for anywhere, then start watching the ride.
struct StartRideView: View {
    @Environment(SavedPlacesStore.self) private var savedPlaces
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var error: DockFinderError?
    @State private var outcome: AnswerModel = AnswerModel()

    var body: some View {
        NavigationStack {
            List {
                if outcome.phase != .idle {
                    Section {
                        AnswerView(phase: outcome.phase)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if !savedPlaces.places.isEmpty {
                    Section("Saved Places") {
                        ForEach(savedPlaces.places) { place in
                            Button {
                                Task { await start(place.name) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                    Text("Alert at \(Speech.length(place.alertDistance))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
                Section("Somewhere Else") {
                    HStack {
                        TextField("Address or place, e.g. Union Square", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button("Search") { Task { await search() } }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error {
                        Text(error.localizedStringResource)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { result in
                        Button {
                            Task { await start(query) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                if let address = result.address {
                                    Text(address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
                Section {
                    AlwaysLocationNotice()
                } footer: {
                    Text("Hands-free: “Hey Siri, ask Dock Finder”, then “start a ride to school”.")
                }
            }
            .navigationTitle("Start a Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        do {
            results = Array(try await MapKitPlaceSearch().search(query).prefix(5))
            error = nil
        } catch let failure as DockFinderError {
            results = []
            error = failure
        } catch {}
    }

    /// Goes through the same path as Siri, so "already there" and the
    /// permission caveat behave the same way.
    private func start(_ destination: String) async {
        if LocationService.shared.authorizationStatus == .notDetermined {
            _ = await LocationService.shared.requestWhenInUseAuthorization()
        }
        await outcome.run {
            try await AssistantRouter.live().handle(.startRide(destination))
        }
        if case .answered = outcome.phase, RideTracker.shared.currentRide != nil {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }
}
