//
//  DockLookupSection.swift
//  Dock Finder
//

import SwiftUI

/// A find button plus its result, shared by the home and Siri screens.
struct DockLookupSection: View {
    let buttonTitle: LocalizedStringKey
    let prominent: Bool

    @State private var model = DockLookupModel()

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
            .disabled(model.phase == .searching)

            switch model.phase {
            case .idle:
                EmptyView()
            case .searching:
                ProgressView("Checking live availability…")
            case .found(let result):
                DockResultCard(result: result)
            case .failed(let error):
                DockErrorCard(error: error)
            }
        }
        .animation(.default, value: model.phase)
    }

    private var findButton: some View {
        Button {
            Task { await model.findNearestDock() }
        } label: {
            Label(buttonTitle, systemImage: "location.fill")
                .frame(maxWidth: .infinity)
        }
    }
}

private struct DockResultCard: View {
    let result: DockSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(result.station.name, systemImage: "bicycle")
                .font(.headline)

            Text(result.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let observedAt = result.station.observedAt {
                Text("Station reported \(observedAt, format: .relative(presentation: .named)). Availability can change at any time.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let mapsURL {
                Link(destination: mapsURL) {
                    Label("Open in Maps", systemImage: "map")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(result.station.latitude),\(result.station.longitude)"),
            URLQueryItem(name: "q", value: result.station.name),
        ]
        return components?.url
    }
}

private struct DockErrorCard: View {
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
