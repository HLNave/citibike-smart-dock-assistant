//
//  DockLookupSection.swift
//  Dock Finder
//

import SwiftUI

/// A "find nearest dock" button plus its result, shared by the home and Siri screens.
struct DockLookupSection: View {
    let buttonTitle: LocalizedStringKey
    let prominent: Bool

    @State private var model = AnswerModel()

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if prominent {
                    findButton.buttonStyle(.borderedProminent)
                } else {
                    findButton.buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .disabled(model.isLoading)

            AnswerView(phase: model.phase)
        }
        .animation(.default, value: model.phase)
    }

    private var findButton: some View {
        Button {
            Task {
                await model.run(needsLocation: true) {
                    try await DockFinderService.live.findNearestDock().answer
                }
            }
        } label: {
            Label(buttonTitle, systemImage: "location.fill")
                .frame(maxWidth: .infinity)
        }
    }
}

/// Shows whatever phase a lookup is in: nothing, a spinner, the answer, or the error.
struct AnswerView: View {
    let phase: AnswerModel.Phase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Checking live availability…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .answered(let answer):
            AnswerCard(answer: answer)
        case .failed(let error):
            ErrorCard(error: error)
        }
    }
}

struct AnswerCard: View {
    let answer: DockAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let station = answer.station {
                Label(station.name, systemImage: "bicycle")
                    .font(.headline)
            }

            Text(answer.text)
                .font(answer.station == nil ? .body : .subheadline)
                .foregroundStyle(answer.station == nil ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let station = answer.station {
                if let observedAt = station.observedAt {
                    Text("Station reported \(observedAt, format: .relative(presentation: .named)). Distances are in a straight line, and availability can change at any time.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DirectionsLinks(station: station)
            }

            if answer.source != .onDevice {
                Label(sourceDescription, systemImage: answer.source == .server ? "cloud" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var sourceDescription: LocalizedStringKey {
        answer.source == .server
            ? "Answered by the Dock Finder server"
            : "Understood by Apple Intelligence on your iPhone"
    }
}

/// Cycling directions to a station.
struct DirectionsLinks: View {
    let station: DockStation

    var body: some View {
        HStack(spacing: 20) {
            if let appleMaps {
                Link(destination: appleMaps) {
                    Label("Apple Maps", systemImage: "map")
                }
            }
            if let googleMaps {
                Link(destination: googleMaps) {
                    Label("Google Maps", systemImage: "bicycle")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private var coordinate: String { "\(station.latitude),\(station.longitude)" }

    private var appleMaps: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: coordinate),
            URLQueryItem(name: "q", value: station.name),
        ]
        return components?.url
    }

    /// Google Maps supports a cycling mode in its universal link.
    private var googleMaps: URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: coordinate),
            URLQueryItem(name: "travelmode", value: "bicycling"),
        ]
        return components?.url
    }
}

struct ErrorCard: View {
    let error: DockFinderError

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(error.localizedStringResource)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline)

            if error == .locationPermissionDenied {
                OpenSettingsButton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label("Open Settings", systemImage: "gear")
        }
        .font(.subheadline.weight(.semibold))
    }
}
