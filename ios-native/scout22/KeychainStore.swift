import Foundation
import Security

/// Keychain-backed storage for the Supabase session (AUDIT P1-1) — replaces
/// the plaintext UserDefaults plist + App Group token mirror. One generic-
/// password item, shared with the share extension through the App Group
/// keychain access group (on iOS an App Group ID is a valid
/// kSecAttrAccessGroup, and both targets already hold the group entitlement).
/// kSecAttrAccessibleAfterFirstUnlock so a background relaunch can restore
/// the session. This file is compiled into BOTH targets.
enum KeychainStore {
    private static let service = "com.jobtok.supabase"
    private static let account = "session"
    private static let accessGroup = SharedConstants.appGroupID

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Could not store the session securely (Keychain error \(status))."
            }
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    static func save(_ data: Data) throws {
        // Delete-then-add keeps the accessibility attribute authoritative.
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// The persistence seam AppSessionStore writes the encoded session through —
/// injectable so tests can run against an in-memory store.
protocol SessionPersisting {
    func save(_ data: Data) throws
    func load() -> Data?
    func clear()
}

struct KeychainSessionPersistence: SessionPersisting {
    func save(_ data: Data) throws { try KeychainStore.save(data) }
    func load() -> Data? { KeychainStore.load() }
    func clear() { KeychainStore.delete() }
}
