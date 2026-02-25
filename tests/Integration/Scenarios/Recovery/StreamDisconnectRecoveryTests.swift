import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Stream Disconnect Recovery Tests

/// Tests for event stream disconnect/reconnect flows using ContainerStateReducer
/// and ContainerStateHolder. Validates state transitions through disconnect,
/// resync snapshot, and reconnect-with-since patterns.
final class StreamDisconnectRecoveryTests: XCTestCase {
    // MARK: - Mock Tests

    func testStreamDisconnectTransitionsToDisconnectedState() {
        let holder = ContainerStateHolder()

        // Apply initial snapshot with a running container
        let container = ContainerSummaryFactory.make(
            id: "c1",
            name: "web-server",
            status: "Up 5 minutes"
        )
        holder.applySnapshot([container], at: Date(timeIntervalSince1970: 1_000_000))

        // Apply some events normally
        let event0 = EventEnvelopeFactory.make(
            sequence: 0,
            containerId: "c1",
            action: "start"
        )
        let action0 = holder.applyEvent(event0)
        XCTAssertEqual(action0, .none)

        // Simulate stream disconnect
        let disconnectTime = Date(timeIntervalSince1970: 1_000_100)
        holder.markDisconnected(at: disconnectTime)

        let state = holder.state
        if case let .disconnected(at) = state.syncStatus {
            XCTAssertEqual(at, disconnectTime)
        } else {
            XCTFail("Expected disconnected status, got \(state.syncStatus)")
        }

        // Container data should still be present
        XCTAssertEqual(state.containers.count, 1)
        XCTAssertNotNil(state.containers["c1"])
    }

    func testResyncAfterDisconnectReplacesContainerState() {
        let holder = ContainerStateHolder()

        // Initial state with two containers
        let containers = [
            ContainerSummaryFactory.make(id: "c1", name: "web", status: "Up"),
            ContainerSummaryFactory.make(id: "c2", name: "db", status: "Up"),
        ]
        holder.applySnapshot(containers, at: Date(timeIntervalSince1970: 1_000_000))

        // Disconnect
        holder.markDisconnected(at: Date(timeIntervalSince1970: 1_000_100))

        // Resync with a different container set (c2 removed, c3 added)
        let resyncContainers = [
            ContainerSummaryFactory.make(id: "c1", name: "web", status: "Up"),
            ContainerSummaryFactory.make(id: "c3", name: "cache", status: "Up"),
        ]
        let resyncTime = Date(timeIntervalSince1970: 1_000_200)
        holder.applyResyncSnapshot(resyncContainers, at: resyncTime)

        let state = holder.state
        if case let .synced(since) = state.syncStatus {
            XCTAssertEqual(since, resyncTime)
        } else {
            XCTFail("Expected synced status after resync, got \(state.syncStatus)")
        }

        XCTAssertEqual(state.containers.count, 2)
        XCTAssertNotNil(state.containers["c1"])
        XCTAssertNil(state.containers["c2"], "c2 should be gone after resync")
        XCTAssertNotNil(state.containers["c3"], "c3 should appear after resync")
        XCTAssertNil(state.lastEventSequence, "Resync should reset event sequence")
    }

    func testReconnectWithSinceReplaysEvents() {
        let holder = ContainerStateHolder()

        // Initial snapshot
        let container = ContainerSummaryFactory.make(
            id: "c1",
            name: "app",
            status: "Up"
        )
        holder.applySnapshot([container], at: Date(timeIntervalSince1970: 1_000_000))

        // First stream session: events 0, 1, 2
        for seq in UInt64(0) ... 2 {
            let event = EventEnvelopeFactory.make(
                sequence: seq,
                containerId: "c1",
                action: "start"
            )
            holder.applyEvent(event)
        }

        XCTAssertEqual(holder.state.lastEventSequence, 2)

        // Disconnect
        holder.markDisconnected(at: Date(timeIntervalSince1970: 1_000_100))

        // Resync (full snapshot replacement)
        let resyncContainer = ContainerSummaryFactory.make(
            id: "c1",
            name: "app",
            status: "Exited"
        )
        holder.applyResyncSnapshot([resyncContainer], at: Date(timeIntervalSince1970: 1_000_200))

        // After resync, sequence is nil, so next event with seq 0 is accepted
        let newEvent0 = EventEnvelopeFactory.make(
            sequence: 0,
            containerId: "c1",
            action: "start"
        )
        let action = holder.applyEvent(newEvent0)
        XCTAssertEqual(action, .none)
        XCTAssertEqual(holder.state.lastEventSequence, 0)

        // Container status was updated by the start event
        let updatedContainer = holder.state.containers["c1"]
        XCTAssertNotNil(updatedContainer)
        XCTAssertTrue(updatedContainer?.status.contains("Up") ?? false)
    }

    func testMultipleDisconnectReconnectCycles() {
        let holder = ContainerStateHolder()

        for cycle in 0 ..< 3 {
            let baseTime = Date(timeIntervalSince1970: Double(1_000_000 + cycle * 1000))

            // Apply snapshot
            let container = ContainerSummaryFactory.make(
                id: "c1",
                name: "app",
                status: "Up"
            )
            if cycle == 0 {
                holder.applySnapshot([container], at: baseTime)
            } else {
                holder.applyResyncSnapshot([container], at: baseTime)
            }

            // Apply a few events
            for seq in UInt64(0) ... 2 {
                let event = EventEnvelopeFactory.make(
                    sequence: seq,
                    containerId: "c1",
                    action: "start",
                    eventAt: baseTime.addingTimeInterval(Double(seq))
                )
                holder.applyEvent(event)
            }

            // Disconnect
            holder.markDisconnected(at: baseTime.addingTimeInterval(10))

            if case .disconnected = holder.state.syncStatus {
                // Expected
            } else {
                XCTFail("Cycle \(cycle): expected disconnected status")
            }
        }

        // After 3 cycles, state should be disconnected
        XCTAssertEqual(holder.state.containers.count, 1)
        XCTAssertNotNil(holder.state.containers["c1"])
    }

    func testActionDuringDisconnectReflectsInResync() {
        let holder = ContainerStateHolder()

        // Initial snapshot with running container
        let container = ContainerSummaryFactory.make(
            id: "c1",
            name: "app",
            status: "Up"
        )
        holder.applySnapshot([container], at: Date(timeIntervalSince1970: 1_000_000))

        // Apply initial events
        let event0 = EventEnvelopeFactory.make(sequence: 0, containerId: "c1", action: "start")
        holder.applyEvent(event0)

        // Disconnect
        holder.markDisconnected(at: Date(timeIntervalSince1970: 1_000_100))

        // During disconnect, the actual container was stopped externally.
        // We simulate this by resyncing with the stopped state.
        let stoppedContainer = ContainerSummaryFactory.make(
            id: "c1",
            name: "app",
            status: "Exited (0) 5 seconds ago"
        )
        holder.applyResyncSnapshot([stoppedContainer], at: Date(timeIntervalSince1970: 1_000_200))

        let state = holder.state
        let c1 = state.containers["c1"]
        XCTAssertNotNil(c1)
        XCTAssertTrue(
            c1?.status.contains("Exited") ?? false,
            "Resync should show the container as exited"
        )
    }

    // MARK: - Real Docker Tests

    func testRealDockerDisconnectAndResync() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let adapter = CLIEngineAdapter()
        let runID = "disconnect-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        let handles: [FixtureHandle]
        do {
            handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "disconnect-test")],
                desiredStates: [.running]
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        let holder = ContainerStateHolder()

        // Initial list as snapshot
        let initialContainers = try await adapter.listContainers()
        holder.applySnapshot(initialContainers, at: Date())

        let containerId = handles[0].containerId
        XCTAssertNotNil(
            holder.state.containers[containerId],
            "Fixture container should be in initial snapshot"
        )

        // Simulate disconnect
        holder.markDisconnected(at: Date())

        // Stop the container during "disconnect"
        try await adapter.stopContainer(id: containerId, timeoutSeconds: 5)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Resync via fresh list
        let resyncContainers = try await adapter.listContainers()
        holder.applyResyncSnapshot(resyncContainers, at: Date())

        let resyncedContainer = holder.state.containers[containerId]
        XCTAssertNotNil(resyncedContainer, "Container should still exist after stop")
        XCTAssertTrue(
            resyncedContainer?.status.lowercased().contains("exited") ?? false,
            "Container should show as exited after resync"
        )
    }

    func testRealDockerReconnectWithSinceReplay() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let adapter = CLIEngineAdapter()
        let runID = "reconnect-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        let handles: [FixtureHandle]
        do {
            handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "reconnect-test")],
                desiredStates: [.running]
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        let containerId = handles[0].containerId
        let beforeStop = Date()

        // Stop container (generates die/stop events)
        try await adapter.stopContainer(id: containerId, timeoutSeconds: 5)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Reconnect with --since to replay the stop events
        let stream = adapter.streamEvents(since: beforeStop)

        let collectTask = Task { () -> [EventEnvelope] in
            var events: [EventEnvelope] = []
            for try await envelope in stream {
                if envelope.containerId == containerId {
                    events.append(envelope)
                    if events.count >= 2 {
                        break
                    }
                }
            }
            return events
        }

        let timeout = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000)
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

        XCTAssertGreaterThanOrEqual(
            events.count, 1,
            "Reconnect with --since should replay at least one event for the stopped container"
        )
    }
}
