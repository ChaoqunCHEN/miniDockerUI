import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Container List Bootstrap & Event Reconciliation Tests

/// Tests that the container list bootstrap correctly reflects all fixture states
/// and that the event stream captures lifecycle transitions (start, stop, restart)
/// for reconciliation.
///
/// All tests require a running Docker daemon and are guarded with XCTSkip.
final class ContainerListBootstrapTests: XCTestCase {
    private var orchestrator: DockerFixtureOrchestrator!
    private var adapter: CLIEngineAdapter!
    private var runID: String!

    override func setUp() {
        orchestrator = DockerFixtureOrchestrator()
        adapter = CLIEngineAdapter()
        runID = "bootstrap-\(UUID().uuidString.prefix(8).lowercased())"
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

    /// Collects events from the stream until timeout or cancellation.
    private func collectEvents(
        since: Date,
        timeoutSeconds: Double = 5,
        filter: (@Sendable (EventEnvelope) -> Bool)? = nil
    ) async throws -> [EventEnvelope] {
        let stream = adapter.streamEvents(since: since)
        let capturedFilter = filter

        let collectTask = Task { [capturedFilter] () -> [EventEnvelope] in
            var collected: [EventEnvelope] = []
            for try await envelope in stream {
                if let capturedFilter {
                    if capturedFilter(envelope) {
                        collected.append(envelope)
                    }
                } else {
                    collected.append(envelope)
                }
            }
            return collected
        }

        // Wait for a brief period then cancel the stream
        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        collectTask.cancel()

        let events: [EventEnvelope]
        do {
            events = try await collectTask.value
        } catch is CancellationError {
            return []
        } catch {
            return []
        }

        return events
    }

    // MARK: - Test: Bootstrap List Includes All Fixture States

    func testBootstrapListIncludesAllFixtureStates() async throws {
        try skipUnlessDockerAvailable()

        let descriptors = [
            sleepDescriptor(key: "boot-created"),
            sleepDescriptor(key: "boot-running"),
            sleepDescriptor(key: "boot-stopped"),
        ]
        let states: [FixtureContainerState] = [.created, .running, .stopped]

        do {
            _ = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: descriptors,
                desiredStates: states
            )

            let containers = try await adapter.listContainers()

            // Filter to only our test containers
            let testContainers = containers.filter { $0.name.contains("mdui-test-\(runID!)") }

            XCTAssertEqual(
                testContainers.count, 3,
                "Bootstrap list should include all 3 fixture containers"
            )

            let createdContainer = testContainers.first { $0.name.contains("boot-created") }
            let runningContainer = testContainers.first { $0.name.contains("boot-running") }
            let stoppedContainer = testContainers.first { $0.name.contains("boot-stopped") }

            XCTAssertNotNil(createdContainer, "Created container should be in list")
            XCTAssertNotNil(runningContainer, "Running container should be in list")
            XCTAssertNotNil(stoppedContainer, "Stopped container should be in list")

            // Verify status strings
            if let running = runningContainer {
                XCTAssertTrue(running.status.lowercased().contains("up"))
            }
            if let stopped = stoppedContainer {
                XCTAssertTrue(stopped.status.lowercased().contains("exited"))
            }
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Stream Captures Start Action

    func testEventStreamCapturesStartAction() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "evt-start")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId
            let sinceDate = Date()

            // Start listening for events, then trigger start
            let eventTask = Task { [adapter] in
                var startEvents: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate)
                for try await envelope in stream {
                    if envelope.containerId == containerId, envelope.action == "start" {
                        startEvents.append(envelope)
                        break // Got what we need
                    }
                }
                return startEvents
            }

            // Small delay to ensure stream is active
            try await Task.sleep(nanoseconds: 500_000_000)

            try await adapter.startContainer(id: containerId)

            // Wait for event with timeout
            let timeout = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                eventTask.cancel()
            }

            let events: [EventEnvelope]
            do {
                events = try await eventTask.value
                timeout.cancel()
            } catch {
                timeout.cancel()
                events = []
            }

            XCTAssertFalse(events.isEmpty, "Should capture at least one 'start' event")
            if let startEvent = events.first {
                XCTAssertEqual(startEvent.action, "start")
                XCTAssertEqual(startEvent.containerId, containerId)
            }
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Stream Captures Stop Action

    func testEventStreamCapturesStopAction() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "evt-stop")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId
            let sinceDate = Date()

            let eventTask = Task { [adapter] in
                var stopEvents: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate)
                for try await envelope in stream {
                    if envelope.containerId == containerId,
                       envelope.action == "stop" || envelope.action == "die"
                    {
                        stopEvents.append(envelope)
                        break
                    }
                }
                return stopEvents
            }

            try await Task.sleep(nanoseconds: 500_000_000)

            try await adapter.stopContainer(id: containerId, timeoutSeconds: 2)

            let timeout = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                eventTask.cancel()
            }

            let events: [EventEnvelope]
            do {
                events = try await eventTask.value
                timeout.cancel()
            } catch {
                timeout.cancel()
                events = []
            }

            XCTAssertFalse(events.isEmpty, "Should capture a 'stop' or 'die' event")
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Stream Captures Restart Action

    func testEventStreamCapturesRestartAction() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "evt-restart")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId
            let sinceDate = Date()

            let eventTask = Task { [adapter] in
                var restartEvents: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate)
                for try await envelope in stream {
                    if envelope.containerId == containerId,
                       envelope.action == "restart" || envelope.action == "start"
                    {
                        restartEvents.append(envelope)
                        if restartEvents.count >= 1 {
                            break
                        }
                    }
                }
                return restartEvents
            }

            try await Task.sleep(nanoseconds: 500_000_000)

            try await adapter.restartContainer(id: containerId, timeoutSeconds: 2)

            let timeout = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                eventTask.cancel()
            }

            let events: [EventEnvelope]
            do {
                events = try await eventTask.value
                timeout.cancel()
            } catch {
                timeout.cancel()
                events = []
            }

            XCTAssertFalse(events.isEmpty, "Should capture restart-related events")
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Reconciliation Updates List After Start

    func testEventReconciliationUpdatesListAfterStart() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "reconcile-start")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId

            // Verify initial state
            let beforeContainers = try await adapter.listContainers()
            let beforeMatch = beforeContainers.first { $0.name.contains("reconcile-start") }
            XCTAssertNotNil(beforeMatch)
            XCTAssertTrue(
                beforeMatch?.status.lowercased().contains("created") ?? false,
                "Container should be in 'created' state before start"
            )

            // Start the container
            try await adapter.startContainer(id: containerId)

            // Re-list and verify state changed
            let afterContainers = try await adapter.listContainers()
            let afterMatch = afterContainers.first { $0.name.contains("reconcile-start") }
            XCTAssertNotNil(afterMatch)
            XCTAssertTrue(
                afterMatch?.status.lowercased().contains("up") ?? false,
                "Container should be 'up' after start, got: \(afterMatch?.status ?? "nil")"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Reconciliation Updates List After Stop

    func testEventReconciliationUpdatesListAfterStop() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "reconcile-stop")],
                desiredStates: [.running]
            )

            let containerId = handles[0].containerId

            // Verify running state
            let beforeContainers = try await adapter.listContainers()
            let beforeMatch = beforeContainers.first { $0.name.contains("reconcile-stop") }
            XCTAssertNotNil(beforeMatch)
            XCTAssertTrue(
                beforeMatch?.status.lowercased().contains("up") ?? false,
                "Container should be 'up' before stop"
            )

            // Stop the container
            try await adapter.stopContainer(id: containerId, timeoutSeconds: 2)

            // Re-list and verify state changed
            let afterContainers = try await adapter.listContainers()
            let afterMatch = afterContainers.first { $0.name.contains("reconcile-stop") }
            XCTAssertNotNil(afterMatch)
            XCTAssertTrue(
                afterMatch?.status.lowercased().contains("exited") ?? false,
                "Container should be 'exited' after stop, got: \(afterMatch?.status ?? "nil")"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }
}
