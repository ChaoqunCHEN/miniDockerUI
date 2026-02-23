import Foundation
import Security

/// Protocol for keychain operations, enabling testability via in-memory mocks.
public protocol KeychainStoreProtocol: Sendable {
    /// Read data for a given service/account pair.
    /// Returns `nil` if the item does not exist.
    func read(service: String, account: String) throws -> Data?

    /// Write (or update) data for a given service/account pair.
    func write(service: String, account: String, data: Data) throws

    /// Delete data for a given service/account pair.
    /// Silently succeeds if the item does not exist (idempotent).
    func delete(service: String, account: String) throws
}

/// Concrete keychain store backed by the macOS Keychain Services API.
///
/// Uses `kSecClassGenericPassword` items keyed by service and account.
public struct MacOSKeychainStore: KeychainStoreProtocol, Sendable {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw CoreError.keychainOperationFailed(
                operation: "read",
                osStatus: status
            )
        }

        return result as? Data
    }

    public func write(service: String, account: String, data: Data) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        var status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            status = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw CoreError.keychainOperationFailed(
                operation: "write",
                osStatus: status
            )
        }
    }

    public func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Idempotent: treat "not found" as success.
        if status == errSecItemNotFound {
            return
        }

        guard status == errSecSuccess else {
            throw CoreError.keychainOperationFailed(
                operation: "delete",
                osStatus: status
            )
        }
    }
}
