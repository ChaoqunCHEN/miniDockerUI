import Foundation
import MiniDockerCore
import XCTest

// MARK: - Mock

/// Test double that returns canned results without requiring Docker.
private struct MockDockerChecker: DockerAvailabilityChecking {
    let binaryExistsResult: Bool
    let daemonHealthyResult: Bool

    func binaryExists() -> Bool {
        binaryExistsResult
    }

    func isDaemonHealthy() async -> Bool {
        daemonHealthyResult
    }
}

// MARK: - Tests

final class EnvironmentProviderTests: XCTestCase {
    // MARK: Happy path

    func testPrepareSucceedsWhenDockerAvailable() async throws {
        let checker = MockDockerChecker(binaryExistsResult: true, daemonHealthyResult: true)
        var provider = LocalDockerEnvironmentProvider(checker: checker)
        try await provider.prepare()
        let ep = provider.endpoint()
        XCTAssertEqual(ep.endpointType, .local)
    }

    // MARK: Error paths

    func testPrepareThrowsWhenBinaryMissing() async {
        let checker = MockDockerChecker(binaryExistsResult: false, daemonHealthyResult: false)
        var provider = LocalDockerEnvironmentProvider(checker: checker)
        do {
            try await provider.prepare()
            XCTFail("Expected error")
        } catch let error as CoreError {
            if case let .dependencyNotFound(name, _) = error {
                XCTAssertEqual(name, "docker")
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPrepareThrowsWhenDaemonUnhealthy() async {
        let checker = MockDockerChecker(binaryExistsResult: true, daemonHealthyResult: false)
        var provider = LocalDockerEnvironmentProvider(checker: checker)
        do {
            try await provider.prepare()
            XCTFail("Expected error")
        } catch let error as CoreError {
            if case .endpointUnreachable = error {
                // expected
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: Endpoint shape

    func testEndpointReturnsLocalSocket() {
        let provider = LocalDockerEnvironmentProvider()
        let ep = provider.endpoint()
        XCTAssertEqual(ep.endpointType, .local)
        XCTAssert(ep.address.contains("docker.sock"))
    }

    // MARK: Teardown

    func testTeardownIsIdempotent() async {
        var provider = LocalDockerEnvironmentProvider()
        await provider.teardown()
        await provider.teardown() // No crash
    }

    // MARK: Full lifecycle

    func testFullLifecycle() async throws {
        let checker = MockDockerChecker(binaryExistsResult: true, daemonHealthyResult: true)
        var provider = LocalDockerEnvironmentProvider(checker: checker)
        try await provider.prepare()
        let ep = provider.endpoint()
        XCTAssertEqual(ep.endpointType, .local)
        await provider.teardown()
    }

    // MARK: Real Docker (skip if unavailable)

    func testRealDockerPrepareIfAvailable() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )
        var provider = LocalDockerEnvironmentProvider()
        // This may fail if daemon isn't running — that's ok for CI.
        do {
            try await provider.prepare()
            let ep = provider.endpoint()
            XCTAssertEqual(ep.endpointType, .local)
            await provider.teardown()
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }
}
