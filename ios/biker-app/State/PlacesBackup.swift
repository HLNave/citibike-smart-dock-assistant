//
//  PlacesBackup.swift
//  Dock Finder
//
//  A second copy of the saved places that survives deleting the app, so
//  reinstalling (for example when a free developer install expires) brings
//  back home, school and their docks.
//

import Foundation
import Security

nonisolated protocol PlacesBackup: Sendable {
    func read() -> Data?
    func write(_ data: Data)
}

/// Keeps the saved places in the keychain. iOS keeps an app's keychain
/// items when the app is deleted, so they come back on reinstall, as long
/// as it's the same bundle ID and signing team. That's long-standing iOS
/// behavior rather than a documented promise. It stays on this iPhone (and
/// its encrypted backups); nothing is sent anywhere.
nonisolated struct KeychainPlacesBackup: PlacesBackup {
    static let service = "DockFinder.savedPlaces"
    static let account = "places"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func read() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data) {
        // Readable after the first unlock, so a change made through Siri
        // with the phone locked is still backed up.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
