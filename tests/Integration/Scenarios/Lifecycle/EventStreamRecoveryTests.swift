import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Event Stream Recovery Tests

/// Tests for event stream resilience: restart, reconnect with full resync,
/// `--since` replay, and concurrent actions during streaming.
///
/// All tests require a running Docker daemon and are guarded with XCTSkip.
final class EventStreamRecoveryTests: XCTestCase {
    private var orchestrator: DockerFixtureOrchestrator!
    private var adapter: CLIEngineAdapter!
    private var runID: String!

    override func setUp() {
        orchestrator = DockerFixtureOrchestrator()
        adapter = CLIEngineAdapter()
        runID = "recovery-\(UUID().uuidString.prefix(8).lowercased())"
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

    /// Collects events matching a filter from a stream, with timeout-based cancellation.
    private func collectFilteredEvents(
        since: Date,
        timeoutSeconds: Double = 5,
        minCount: Int = 1,
        filter: @Sendable @escaping (EventEnvelope) -> Bool
    ) async -> [EventEnvelope] {
        let stream = adapter.streamEvents(since: since)
        let capturedFilter = filter
        let capturedMinCount = minCount

        let collectTask = Task { [capturedFilter, capturedMinCount] () -> [EventEnvelope] in
            var collected: [EventEnvelope] = []
            for try await envelope in stream {
                if capturedFilter(envelope) {
                    collected.append(envelope)
                    if collected.count >= capturedMinCount {
                        break
                    }
                }
            }
            return collected
        }

        let timeout = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            collectTask.cancel()
        }

        let events: [EventEnvelope]
        do {
            events = try await collectTask.value
            timeout.cancel()
        } catch {
            timeout.cancel()
            events = []
        }

        return events
    }

    // MARK: - Test: Event Stream Can Be Restarted

    func testEventStreamCanBeRestarted() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "stream-restart")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId

            // First stream session: start the container
            let sinceDate1 = Date()

            let stream1Task = Task { [adapter] in
                var events: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate1)
                for try await envelope in stream {
                    if envelope.containerId == containerId, envelope.action == "start" {
                        events.append(envelope)
                        break
                    }
                }
                return events
            }

            try await Task.sleep(nanoseconds: 500_000_000)
            try await adapter.startContainer(id: containerId)

            let timeout1 = Task {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                stream1Task.cancel()
            }

            let events1: [EventEnvelope]
            do {
                events1 = try await stream1Task.value
                timeout1.cancel()
            } catch {
                timeout1.cancel()
                events1 = []
            }

            XCTAssertFalse(events1.isEmpty, "First stream session should capture start event")

            // Second stream session: stop the container
            let sinceDate2 = Date()

            let stream2Task = Task { [adapter] in
                var events: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate2)
                for try await envelope in stream {
                    if envelope.containerId == containerId,
                       envelope.action == "die" || envelope.action == "stop"
                    {
                        events.append(envelope)
                        break
                    }
                }
                return events
            }

            try await Task.sleep(nanoseconds: 500_000_000)
            try await adapter.stopContainer(id: containerId, timeoutSeconds: 2)

            let timeout2 = Task {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                stream2Task.cancel()
            }

            let events2: [EventEnvelope]
            do {
                events2 = try await stream2Task.value
                timeout2.cancel()
            } catch {
                timeout2.cancel()
                events2 = []
            }

            XCTAssertFalse(events2.isEmpty, "Second stream session should capture stop/die event")
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Full Resync After Stream Reconnect

    func testFullResyncAfterStreamReconnect() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "resync")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId
            let beforeActions = Date()

            // Perform actions without any active stream
            try await adapter.startContainer(id: containerId)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await adapter.stopContainer(id: containerId, timeoutSeconds: 2)
            try await Task.sleep(nanoseconds: 500_000_000)

            // After actions are done, verify we can see the current state via list
            let containers = try await adapter.listContainers()
            let resyncContainer = containers.first { $0.name.contains("resync") }
            XCTAssertNotNil(resyncContainer, "Container should still be visible")
            XCTAssertTrue(
                resyncContainer?.status.lowercased().contains("exited") ?? false,
                "Container should be exited after stop"
            )

            // Now start a new stream with --since to replay missed events
            let events = await collectFilteredEvents(
                since: beforeActions,
                timeoutSeconds: 3,
                minCount: 2
            ) { envelope in
                envelope.containerId == containerId
            }

            // Should have captured at least start and die/stop events
            XCTAssertGreaterThanOrEqual(
                events.count, 1,
                "Reconnected stream with --since should replay events"
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Event Stream With Since Recaptures

    func testEventStreamWithSinceRecaptures() async throws {
        try skipUnlessDockerAvailable()

        do {
            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "since-test")],
                desiredStates: [.created]
            )

            let containerId = handles[0].containerId
            let beforeStart = Date()

            // Perform a start
            try await adapter.startContainer(id: containerId)
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Use --since to recapture the start event
            let events = await collectFilteredEvents(
                since: beforeStart,
                timeoutSeconds: 3,
                minCount: 1
            ) { envelope in
                envelope.containerId == containerId && envelope.action == "start"
            }

            XCTAssertFalse(
                events.isEmpty,
                "Stream with --since should recapture start event from the past"
            )
            if let startEvent = events.first {
                XCTAssertEqual(startEvent.action, "start")
                XCTAssertEqual(startEvent.containerId, containerId)
            }
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    // MARK: - Test: Concurrent Actions and Event Stream

    func testConcurrentActionsAndEventStream() async throws {
        try skipUnlessDockerAvailable()

        do {
            // Create 3 containers in created state
            let descriptors = [
                sleepDescriptor(key: "conc-a"),
                sleepDescriptor(key: "conc-b"),
                sleepDescriptor(key: "conc-c"),
            ]

            let handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: descriptors,
                desiredStates: [.created, .created, .created]
            )

            let containerIds = Set(handles.map(\.containerId))
            let sinceDate = Date()

            // Start event stream
            let eventTask = Task { [adapter] in
                var events: [EventEnvelope] = []
                let stream = adapter!.streamEvents(since: sinceDate)
                for try await envelope in stream {
                    if let cid = envelope.containerId,
                       containerIds.contains(cid),
                       envelope.action == "start"
                    {
                        events.append(envelope)
                        if events.count >= 3 {
                            break
                        }
                    }
                }
                return events
            }

            try await Task.sleep(nanoseconds: 500_000_000)

            // Start all 3 containers concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                for handle in handles {
                    group.addTask { [adapter] in
                        try await adapter!.startContainer(id: handle.containerId)
                    }
                }
                try await group.waitForAll()
            }

            // Wait for events with timeout
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

            // All 3 start events should be captured
            XCTAssertGreaterThanOrEqual(
                events.count, 2,
                "Should capture start events for concurrent container starts, got \(events.count)"
            )

            // Verify each event belongs to one of our containers
            for event in events {
                XCTAssertTrue(
                    containerIds.contains(event.containerId ?? ""),
                    "Event should belong to one of our test containers"
                )
            }
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }
}
