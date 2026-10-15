//
//  Metrics.swift
//  Dock Finder
//
//  Usage events sent to the Dock Finder team's Google Sheet, so the team
//  can measure how riders use the app and what it saves them. Only sent
//  when the rider chose to share (UsageSharing). Each event carries a
//  random per-install ID (never a name or Apple ID), the rider's location
//  at the time, and the docks involved.
//
//  The sheet's address comes from `DOCKFINDER_METRICS_URL` in the
//  gitignored Local.xcconfig (see metrics/README.md). Without it, nothing
//  is sent anywhere.
//

import CoreLocation
import Foundation

/// The rider's answer to "Share usage data with the Dock Finder team?".
nonisolated enum UsageSharing: String, Sendable {
    case granted
    case declined

    static let key = "usageSharing"

    /// `nil` until the rider has been asked.
    static func current(in defaults: UserDefaults = .standard) -> UsageSharing? {
        defaults.string(forKey: key).flatMap(UsageSharing.init(rawValue:))
    }

    static func set(_ choice: UsageSharing, in defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: key)
    }
}

/// One row in the team's sheet.
nonisolated struct MetricsEvent: Codable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let name: String
    let installID: String
    let appVersion: String
    let latitude: Double?
    let longitude: Double?
    let station: String?
    let avoidedStation: String?
    let minutesSaved: Double?
    let dollarsSaved: Double?
    let details: [String: String]
}

final class Metrics {
    static let shared = Metrics()

    nonisolated static let endpointInfoKey = "DockFinderMetricsURL"
    private static let queueKey = "metricsQueue"
    /// Oldest events are dropped beyond this, if the sheet is unreachable for long.
    private static let maxQueued = 1_000
    private static let batchSize = 100

    private let defaults: UserDefaults
    private let endpoint: URL?
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var queue: [MetricsEvent]
    private var isSending = false

    init(
        defaults: UserDefaults = .standard,
        endpoint: URL? = Metrics.configuredEndpoint(),
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.send = send
        queue = defaults.data(forKey: Self.queueKey)
            .flatMap { try? Self.decoder.decode([MetricsEvent].self, from: $0) } ?? []
    }

    var queuedCount: Int { queue.count }

    /// Records an event, if the rider agreed to share, and sends it soon.
    /// Without a `location`, the latest one iOS has is used.
    func log(
        _ name: String,
        station: String? = nil,
        avoidedStation: String? = nil,
        minutesSaved: Double? = nil,
        location: CLLocation? = nil,
        details: [String: String] = [:]
    ) {
        guard UsageSharing.current(in: defaults) == .granted else { return }
        // Looked up here rather than as the parameter's default: default
        // values aren't evaluated on the main actor, and LocationService is.
        let location = location ?? LocationService.shared.lastKnownLocation
        let event = MetricsEvent(
            id: UUID(),
            date: .now,
            name: name,
            installID: AssistantSession.id(defaults: defaults),
            appVersion: Self.appVersion,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            station: station,
            avoidedStation: avoidedStation,
            minutesSaved: minutesSaved.map { ($0 * 10).rounded() / 10 },
            dollarsSaved: minutesSaved.map { (SavingsModel.dollars(forMinutes: $0) * 100).rounded() / 100 },
            details: details
        )
        queue.append(event)
        if queue.count > Self.maxQueued { queue.removeFirst(queue.count - Self.maxQueued) }
        save()
        Task { await flush() }
    }

    /// Sends queued events in batches. Failed sends stay queued and are
    /// retried with the next event or at the next launch.
    func flush() async {
        guard let endpoint, !isSending, UsageSharing.current(in: defaults) == .granted else { return }
        isSending = true
        defer { isSending = false }
        while !queue.isEmpty {
            let batch = Array(queue.prefix(Self.batchSize))
            var request = URLRequest(url: endpoint, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let body = try? Self.encoder.encode(["events": batch]) else { return }
            request.httpBody = body
            guard let result = try? await send(request),
                  let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return }
            let sent = Set(batch.map(\.id))
            queue.removeAll { sent.contains($0.id) }
            save()
        }
    }

    /// When the rider stops sharing, anything not yet sent is deleted.
    func discardQueued() {
        queue.removeAll()
        save()
    }

    private func save() {
        defaults.set(try? Self.encoder.encode(queue), forKey: Self.queueKey)
    }

    // MARK: - Configuration

    /// The Google Apps Script web app URL, without "https://" (xcconfig
    /// files treat "//" as a comment), e.g. "script.google.com/macros/s/…/exec".
    nonisolated static func configuredEndpoint(in bundle: Bundle = .main) -> URL? {
        (bundle.object(forInfoDictionaryKey: endpointInfoKey) as? String).flatMap(endpoint(from:))
    }

    nonisolated static func endpoint(from value: String) -> URL? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("$(") else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    private nonisolated static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
