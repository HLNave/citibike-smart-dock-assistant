//
//  Metrics.swift
//  Dock Finder
//
//  Usage events sent to the Dock Finder team's Google Sheet, so the team
//  can measure how riders use the app and what it saves them. Only sent
//  when the rider chose to share (UsageSharing). Each event carries a
//  random per-install ID (not an Apple ID), the name the rider chose to
//  give, if any, the rider's location at the time, and the docks involved.
//
//  The sheet's address comes from `DOCKFINDER_METRICS_URL`, committed in
//  Config/DockFinder.xcconfig. Setting it empty in the gitignored
//  Local.xcconfig sends nothing anywhere (see metrics/README.md).
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

    static let nameKey = "usageName"

    /// What the rider asked to be called in the team's sheet, so testers can
    /// be told apart. Optional; `nil` when blank.
    static func name(in defaults: UserDefaults = .standard) -> String? {
        let name = defaults.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func setName(_ name: String, in defaults: UserDefaults = .standard) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if trimmed.isEmpty {
            defaults.removeObject(forKey: nameKey)
        } else {
            defaults.set(trimmed, forKey: nameKey)
        }
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
    /// The rider's chosen name; `nil` if they didn't give one (and in
    /// events queued by builds before names existed).
    var userName: String? = nil
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

    /// Opening the app counts toward the team's Users tab (last opened,
    /// how often). Coming back within this long is the same visit.
    static let sameVisit: TimeInterval = 10 * 60
    private static let lastOpenedKey = "metricsLastOpened"

    /// Called whenever the app comes to the foreground; not for background
    /// relaunches (rides, arrival alerts), which aren't the rider opening it.
    func logOpened(now: Date = .now) {
        if let last = defaults.object(forKey: Self.lastOpenedKey) as? Date,
           now.timeIntervalSince(last) < Self.sameVisit, now >= last {
            return
        }
        defaults.set(now, forKey: Self.lastOpenedKey)
        log("app_opened", location: nil)
    }

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
            details: details,
            userName: UsageSharing.name(in: defaults)
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
            guard let result = try? await send(request), Self.sheetSaved(result) else { return }
            let sent = Set(batch.map(\.id))
            queue.removeAll { sent.contains($0.id) }
            save()
        }
    }

    /// Whether the sheet stored the batch. Apps Script answers 200 even
    /// when the script fails, so the status alone isn't enough: only a
    /// reply of `{"ok": true}` counts. Anything else (`{"ok": false}`, or
    /// Google's HTML error page) keeps the batch queued for a retry.
    nonisolated static func sheetSaved(_ result: (Data, URLResponse)) -> Bool {
        guard let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let reply = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
        else { return false }
        return reply["ok"] as? Bool == true
    }

    /// What went wrong, for `siri_failed` and `app_failed` rows.
    nonisolated static func errorDetails(_ error: any Error) -> [String: String] {
        switch error {
        case let error as DockFinderError:
            error.metricsDetails
        case is CancellationError:
            ["error": "cancelled"]
        default:
            // Errors from Siri itself, e.g. the rider cancelling a question.
            // Their type name is often just "NSError", so the domain and
            // code are what tell them apart.
            errorDetails(error as NSError)
        }
    }

    private nonisolated static func errorDetails(_ error: NSError) -> [String: String] {
        ["error": "\(error.domain) \(error.code)", "error_text": String(error.localizedDescription.prefix(200))]
    }

    /// How old `location` was when an answer used it, in whole seconds.
    nonisolated static func locationAge(_ location: CLLocation?, now: Date = .now) -> [String: String] {
        guard let location else { return [:] }
        return ["location_age_seconds": String(Int(max(0, now.timeIntervalSince(location.timestamp))))]
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
