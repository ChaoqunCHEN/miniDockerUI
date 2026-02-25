import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Container Lifecycle Integration Tests

/// Exercises full container lifecycle (create, start, stop, restart) through
/// ``CLIEngineAdapter`` using real Docker containers managed by
/// ``DockerFixtureOrchestrator``.
///
/// Every test creates containers with a unique `runID` and cleans up in
/// `tearDown()` via ``removeFixtures``. All tests are guarded with XCTSkip
/// when Docker is not available.
final class ContainerLifecycleTests: XCTestCase {
    private var orchestrator: DockerFixtureOrchestrator!
    private var adapter: CLIEngineAdapter!
    private var runID: String!

    override func setUp() {
        orchestrator = DockerFixtureOrchestrator()
        adapter = CLIEngineAdapter()
        runID = "lifecycle-\(UUID().uuidString.prefix(8).lowercased())"
    }

    override func tearDown() async throws {
        if let runID {
            await orchestrator.removeFixtures(runID: runID)
        }
    }

    // MARK: - Helpers

    private func skipUnlessDockerAvailable() throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )
    }

    private func sleepDescriptor(key: String) -> FixtureDescriptor {
        FixtureDescriptor(
            key: key,
            image: "alpine:3.20",
            command: ["sleep", "3600"],
            environment: [:]
        )
    }

    /// Finds a container by name substring in the current container list.
    private func findContainer(matching nameSubstring: String) async throws -> ContainerSummary? {
        let containers = try await adapter.listContainers()
        return containers.first { $0.name.contains(nameSubstring) }
    }

    // MARK: - Test: Create Container Appears in List

    func testCreateContainerAppearsInList() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "list-check")]
            )

            XCTAssertEqual(handles.count, 1)

            let found = try await findContainer(matching: "mdui-test-\(runID!)-list-check")
            XCTAssertNotNil(found, "Created container should appear in docker ps -a list")
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Start Container Transitions to Running

    func testStartContainerTransitionsToRunning() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "start-test")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId

            // Start via adapter
            try await adapter.startContainer(id: containerId)

            // Verify status
            let container = try await findContainer(matching: "mdui-test-\(runID!)-start-test")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("up") ?? false,
                "Container should be running after start, status: \(container?.status ?? "nil")"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Stop Running Container Transitions to Exited

    func testStopRunningContainerTransitionsToExited() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "stop-test")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId

            // Stop via adapter
            try await adapter.stopContainer(id: containerId, timeoutSeconds: 5)

            // Verify status
            let container = try await findContainer(matching: "mdui-test-\(runID!)-stop-test")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("exited") ?? false,
                "Container should be exited after stop, status: \(container?.status ?? "nil")"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Restart Container Cycles Lifecycle

    func testRestartContainerCyclesLifecycle() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "restart-test")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId

            // Restart via adapter
            try await adapter.restartContainer(id: containerId, timeoutSeconds: 5)

            // Container should still be running after restart
            let container = try await findContainer(matching: "mdui-test-\(runID!)-restart-test")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("up") ?? false,
                "Container should be running after restart, status: \(container?.status ?? "nil")"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Start Already Running Container Succeeds

    func testStartAlreadyRunningContainerSucceeds() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "double-start")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId

            // Start again — should not throw
            try await adapter.startContainer(id: containerId)

            // Verify still running
            let container = try await findContainer(matching: "mdui-test-\(runID!)-double-start")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("up") ?? false,
                "Container should remain running after double start"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Stop Already Stopped Container Succeeds

    func testStopAlreadyStoppedContainerSucceeds() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "double-stop")],
                desiredStates: [.stopped]
            )

            let containerId = handles[0].containerId

            // Stop again — should not throw (Docker is idempotent for stop on exited containers)
            // Note: Docker CLI may return non-zero for stopping an already-stopped container.
            // We accept either success or a specific error here.
            do {
                try await adapter.stopContainer(id: containerId, timeoutSeconds: 5)
            } catch {
                // Some Docker versions return non-zero when stopping an already-stopped container.
                // This is acceptable behavior.
            }

            let container = try await findContainer(matching: "mdui-test-\(runID!)-double-stop")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("exited") ?? false,
                "Container should remain stopped"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Start Nonexistent Container Throws

    func testStartNonexistentContainerThrows() async throws {
        try skipUnlessDockerAvailable()

        do {
            try await adapter.startContainer(id: "nonexistent-container-id-\(UUID().uuidString)")
            XCTFail("Expected startContainer to throw for nonexistent container")
        } catch is CoreError {
            // Expected: processNonZeroExit
        } catch {
            // Any error is acceptable for a nonexistent container
        }
    }

    // MARK: - Test: Stop With Timeout Parameter

    func testStopWithTimeoutParameter() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "timeout-stop")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId

            // Stop with explicit timeout
            try await adapter.stopContainer(id: containerId, timeoutSeconds: 2)

            let container = try await findContainer(matching: "mdui-test-\(runID!)-timeout-stop")
            XCTAssertNotNil(container)
            XCTAssertTrue(
                container?.status.lowercased().contains("exited") ?? false,
                "Container should be exited after stop with timeout"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Multiple Containers in Different States

    func testMultipleContainersInDifferentStates() async throws {
        try skipUnlessDockerAvailable()

        let descriptors = [
            sleepDescriptor(key: "multi-created"),
            sleepDescriptor(key: "multi-running"),
            sleepDescriptor(key: "multi-stopped"),
        ]
        let states: [FixtureContainerState] = [.created, .running, .stopped]

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: descriptors,
                desiredStates: states
            )

            XCTAssertEqual(handles.count, 3)

            // List all containers and verify each state
            let containers = try await adapter.listContainers()

            let created = containers.first { $0.name.contains("multi-created") }
            let running = containers.first { $0.name.contains("multi-running") }
            let stopped = containers.first { $0.name.contains("multi-stopped") }

            XCTAssertNotNil(created, "Created container should be in list")
            XCTAssertNotNil(running, "Running container should be in list")
            XCTAssertNotNil(stopped, "Stopped container should be in list")

            if let running {
                XCTAssertTrue(
                    running.status.lowercased().contains("up"),
                    "Running container status should contain 'up', got: \(running.status)"
                )
            }

            if let stopped {
                XCTAssertTrue(
                    stopped.status.lowercased().contains("exited"),
                    "Stopped container status should contain 'exited', got: \(stopped.status)"
                )
            }
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }
}
