@testable import MiniDockerCore
import XCTest

// MARK: - In-Memory Mock

/// In-memory keychain mock for testing `KeychainStoreProtocol` logic
/// without requiring real keychain entitlements.
private final class InMemoryKeychainStore: KeychainStoreProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }

    func read(service: String, account: String) throws -> Data? {
        storage[key(service: service, account: account)]
    }

    func write(service: String, account: String, data: Data) throws {
        storage[key(service: service, account: account)] = data
    }

    func delete(service: String, account: String) throws {
        storage.removeValue(forKey: key(service: service, account: account))
    }
}

// MARK: - Tests

final class KeychainStoreTests: XCTestCase {
    func testProtocolConformance() {
        // Verify that MacOSKeychainStore conforms to KeychainStoreProtocol at compile time.
        let store: any KeychainStoreProtocol = MacOSKeychainStore()
        XCTAssertNotNil(store)
    }

    func testMockWriteAndRead() throws {
        let store = InMemoryKeychainStore()
        let testData = Data("secret-token".utf8)

        try store.write(service: "com.test.app", account: "user1", data: testData)
        let result = try store.read(service: "com.test.app", account: "user1")

        XCTAssertEqual(result, testData)
    }

    func testMockReadNonexistentReturnsNil() throws {
        let store = InMemoryKeychainStore()

        let result = try store.read(service: "com.test.app", account: "nonexistent")
        XCTAssertNil(result)
    }

    func testMockDeleteIsIdempotent() throws {
        let store = InMemoryKeychainStore()

        // Delete a key that was never written; should not crash or throw.
        XCTAssertNoThrow(try store.delete(service: "com.test.app", account: "missing"))
    }

    func testMockOverwrite() throws {
        let store = InMemoryKeychainStore()
        let firstData = Data("first-value".utf8)
        let secondData = Data("second-value".utf8)

        try store.write(service: "com.test.app", account: "user1", data: firstData)
        try store.write(service: "com.test.app", account: "user1", data: secondData)

        let result = try store.read(service: "com.test.app", account: "user1")
        XCTAssertEqual(result, secondData)
    }

    func testMockDeleteRemovesData() throws {
        let store = InMemoryKeychainStore()
        let testData = Data("to-be-deleted".utf8)

        try store.write(service: "com.test.app", account: "user1", data: testData)
        try store.delete(service: "com.test.app", account: "user1")

        let result = try store.read(service: "com.test.app", account: "user1")
        XCTAssertNil(result)
    }

    func testMockIsolatesByServiceAndAccount() throws {
        let store = InMemoryKeychainStore()
        let data1 = Data("data-for-svc1".utf8)
        let data2 = Data("data-for-svc2".utf8)

        try store.write(service: "svc1", account: "acct", data: data1)
        try store.write(service: "svc2", account: "acct", data: data2)

        XCTAssertEqual(try store.read(service: "svc1", account: "acct"), data1)
        XCTAssertEqual(try store.read(service: "svc2", account: "acct"), data2)
    }
}
