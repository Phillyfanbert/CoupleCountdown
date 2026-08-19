// KeychainStore.swift — shared Keychain access-group read/write helper for app <-> widget (DESIGN.md §5.5)

import Foundation
import Security

/// Reads/writes the Anonymous Auth refresh token (DESIGN.md §5.5) into a
/// Keychain access group shared between the app and widget extension.
/// Mirrors AppGroupCache's degrade-gracefully-to-nil behavior if
/// Keychain Sharing isn't available under a free Personal Team (§5.5's
/// four-outcome fallback tree, §10).
public struct KeychainStore {
    private let accessGroup: String
    private let account: String
    private let service = "com.couplecountdown.auth"

    public init(accessGroup: String, account: String = "refreshToken") {
        self.accessGroup = accessGroup
        self.account = account
    }

    /// Returns whether the write actually succeeded — callers that care
    /// about silent Keychain failures (e.g. entitlement issues, the same
    /// class of bug that caused Firebase Auth's own Keychain write to
    /// fail during CI verification) should check this rather than assume
    /// success, per `@discardableResult` for the callers that don't need
    /// to.
    @discardableResult
    public func write(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery() as CFDictionary) // clear any existing value first
        var query = baseQuery()
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }
}
