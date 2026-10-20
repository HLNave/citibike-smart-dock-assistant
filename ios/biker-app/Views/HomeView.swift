//
//  HomeView.swift
//  Dock Finder
//

import SwiftUI

struct HomeView: View {
    @Environment(SavedPlacesStore.self) private var savedPlaces
    @State private var showsSiriInstructions = false
    @State private var showsAddPlace = false
    /// Riders who finished onboarding before usage sharing existed are
    /// asked once here.
    @State private var asksAboutSharing = UsageSharing.current() == nil
    /// Riders who agreed to share before names existed are asked for one here.
    @State private var asksForName = UsageNameCard.shouldShow

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "bicycle.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Dock Finder")
                            .font(.largeTitle.bold())
                        Text("Find a Citi Bike dock with room, hands-free.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    if asksForName {
                        UsageNameCard { withAnimation { asksForName = false } }
                    }

                    DockLookupSection(buttonTitle: "Find Nearest Dock", prominent: true)

                    GuidanceCard()

                    RideCard()

                    NavigationLink(value: HomeRoute.savings) {
                        SavingsCard()
                    }
                    .buttonStyle(.plain)

                    HomeCard(title: "Saved Places", trailing: savedPlaces.places.count > 1 ? .manage : nil) {
                        if savedPlaces.places.isEmpty {
                            Text("Save school, work or home to check your usual dock there, by voice or with an arrival automation.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(savedPlaces.places) { place in
                            NavigationLink(value: HomeRoute.savedPlace(place.id)) {
                                HomeRow(
                                    title: place.name,
                                    subtitle: place.usualStationName.map { "Usual dock: \($0)" } ?? place.address,
                                    systemImage: "star.fill"
                                )
                            }
                        }
                        Button {
                            showsAddPlace = true
                        } label: {
                            Label("Add a Place", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }

                    HomeCard(title: "More") {
                        NavigationLink(value: HomeRoute.placeSearch) {
                            HomeRow(title: "Dock Near a Place", subtitle: "An address, landmark or neighborhood", systemImage: "mappin.and.ellipse")
                        }
                        NavigationLink(value: HomeRoute.stationSearch) {
                            HomeRow(title: "Check a Station", subtitle: "Is it full? Where to go instead", systemImage: "parkingsign.circle")
                        }
                        NavigationLink(value: HomeRoute.citywide) {
                            HomeRow(title: "Citywide Status", subtitle: "Bikes, open docks, full stations", systemImage: "chart.bar")
                        }
                        NavigationLink(value: HomeRoute.ask) {
                            HomeRow(title: "Ask a Question", subtitle: "Type anything, in your own words", systemImage: "bubble.left")
                        }
                    }

                    Button {
                        showsSiriInstructions = true
                    } label: {
                        Label("How to Use with Siri", systemImage: "mic")
                    }
                    .controlSize(.large)

                    NavigationLink(value: HomeRoute.directions) {
                        Label("Directions", systemImage: "location.north.line")
                            .font(.subheadline)
                    }

                    NavigationLink(value: HomeRoute.privacy) {
                        Label("Privacy", systemImage: "hand.raised")
                            .font(.subheadline)
                    }
                }
                .padding(24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .savedPlace(let id): SavedPlaceView(placeID: id)
                case .managePlaces: ManagePlacesView()
                case .placeSearch: PlaceSearchView()
                case .stationSearch: StationSearchView()
                case .citywide: CitywideView()
                case .ask: AskView()
                case .savings: SavingsView()
                case .directions: DirectionsSettingView()
                case .privacy: PrivacyView()
                }
            }
            .onAppear {
                // Back from Privacy, where they may have added a name or stopped sharing.
                asksForName = UsageNameCard.shouldShow
            }
        }
        .sheet(isPresented: $showsSiriInstructions) {
            NavigationStack {
                SiriInstructionsView(onDone: { showsSiriInstructions = false })
            }
        }
        .sheet(isPresented: $showsAddPlace) {
            AddPlaceView()
        }
        .sheet(isPresented: $asksAboutSharing) {
            UsageSharingPrompt { asksAboutSharing = false }
        }
        .task {
            // For riders who finished onboarding before arrival alerts
            // existed. iOS only ever shows this once.
            await MotionCheck.requestPermission()
        }
    }
}

enum HomeRoute: Hashable {
    case savedPlace(UUID)
    case managePlaces
    case placeSearch
    case stationSearch
    case citywide
    case ask
    case savings
    case directions
    case privacy
}

private struct HomeCard<Content: View>: View {
    enum Trailing { case manage }

    let title: LocalizedStringKey
    var trailing: Trailing? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if trailing == .manage {
                    NavigationLink("Edit", value: HomeRoute.managePlaces)
                        .font(.subheadline)
                }
            }
            content
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

private struct HomeRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

#Preview {
    HomeView()
        .environment(SavedPlacesStore(defaults: UserDefaults(suiteName: "preview")!, onChange: {}))
        .environment(RideTracker(defaults: UserDefaults(suiteName: "preview")!))
}
