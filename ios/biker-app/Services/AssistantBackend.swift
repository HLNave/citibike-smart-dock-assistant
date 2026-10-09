//
//  AssistantBackend.swift
//  Dock Finder
//
//  The n8n workflow's Siri webhook. Used only for free-form questions the
//  app can't understand on device. The host comes from the gitignored
//  `ios/Config/Local.xcconfig` (see ios/README.md) because the webhook has
//  no password; without it, the app works fully offline from n8n.
//

import CoreLocation
import Foundation

nonisolated protocol AssistantBackend: Sendable {
    /// Returns the single spoken sentence the backend produces.
    func ask(_ text: String, location: CLLocation?, sessionID: String) async throws -> String
}

nonisolated struct N8NAssistantClient: AssistantBackend {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let hostInfoKey = "DockFinderBackendHost"
    static let siriWebhookPath = "/webhook/citibike-siri"

    let endpoint: URL
    private let loadData: DataLoader
    private let timeout: TimeInterval

    init(endpoint: URL, timeout: TimeInterval = 20, loadData: @escaping DataLoader = { try await URLSession.shared.data(for: $0) }) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.loadData = loadData
    }

    /// The configured backend, or `nil` if no host was set at build time.
    static func configured(in bundle: Bundle = .main) -> N8NAssistantClient? {
        guard let host = bundle.object(forInfoDictionaryKey: hostInfoKey) as? String else { return nil }
        return endpoint(forHost: host).map { N8NAssistantClient(endpoint: $0) }
    }

    /// Accepts "yourname.app.n8n.cloud" or a full "https://…" base URL.
    static func endpoint(forHost host: String) -> URL? {
        var base = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("$(") else { return nil }
        if !base.contains("://") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + siriWebhookPath), url.host() != nil else { return nil }
        return url
    }

    func ask(_ text: String, location: CLLocation?, sessionID: String) async throws -> String {
        // Same body as the group's "Dock Finder" Siri shortcut.
        var body = ["text": text, "sessionId": sessionID]
        if let coordinate = location?.coordinate {
            body["lat"] = String(coordinate.latitude)
            body["lon"] = String(coordinate.longitude)
        }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loadData(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DockFinderError.backendUnavailable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DockFinderError.backendUnavailable
        }
        let reply = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw DockFinderError.backendUnavailable }
        return Speech.sentence(reply)
    }
}

/// A random per-install ID that keeps this rider's n8n conversation memory
/// separate from everyone else's. Replaces the first name the Shortcuts
/// setup asked for.
nonisolated enum AssistantSession {
    static let key = "assistantSessionID"

    static func id(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) { return existing }
        let created = "app-" + UUID().uuidString.prefix(8).lowercased()
        defaults.set(created, forKey: key)
        return created
    }
}
