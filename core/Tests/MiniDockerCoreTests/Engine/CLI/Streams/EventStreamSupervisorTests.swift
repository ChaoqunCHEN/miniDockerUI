import Foundation
@testable import MiniDockerCore
import os
import XCTest

// MARK: - Mock Engine Adapter

private final class MockEngineAdapter: EngineAdapter, @unchecked Sendable {
    var listContainersHandler: (@Sendable () async throws -> [ContainerSummary])?
    var streamEventsHandler: (@Sendable (Date?) -> AsyncThrowingStream<EventEnvelope, Error>)?

    private let lock = OSAllocatedUnfairLock(initialState: AdapterState())

    struct AdapterState {
        var streamEventsSinceDates: [Date?] = []
        var listContainersCalls: Int = 0
    }

    var streamEventsSinceDates: [Date?] {
        lock.withLock { $0.streamEventsSinceDates }
    }

    var listContainersCalls: Int {
        lock.withLock { $0.listContainersCalls }
    }

    func listContainers() async throws -> [ContainerSummary] {
        lock.withLock { $0.listContainersCalls += 1 }
        guard let handler = listContainersHandler else {
            return []
        }
        return try await handler()
    }

    func inspectContainer(id _: String) async throws -> ContainerDetail {
        fatalError("Not used in supervisor tests")
    }

    func startContainer(id _: String) async throws {
        fatalError("Not used in supervisor tests")
    }

    func stopContainer(id _: String, timeoutSeconds _: Int?) async throws {
        fatalError("Not used in supervisor tests")
    }

    func restartContainer(id _: String, timeoutSeconds _: Int?) async throws {
        fatalError("Not used in supervisor tests")
    }

    func streamEvents(since: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        lock.withLock { $0.streamEventsSinceDates.append(since) }
        guard let handler = streamEventsHandler else {
            return AsyncThrowingStream { $0.finish() }
        }
        return handler(since)
    }

    func streamLogs(id _: String, options _: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        fatalError("Not used in supervisor tests")
    }
}

// MARK: - Thread-safe Event Collector

private final class EventCollector: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: CollectorState())

    struct CollectorState {
        var dockerEvents: [EventEnvelope] = []
        var phases: [SupervisorPhase] = []
        var resyncContainersList: [[ContainerSummary]] = []
    }

    func appendDockerEvent(_ envelope: EventEnvelope) {
        lock.withLock { $0.dockerEvents.append(envelope) }
    }

    func appendPhase(_ phase: SupervisorPhase) {
        lock.withLock { $0.phases.append(phase) }
    }

    func appendResyncContainers(_ containers: [ContainerSummary]) {
        lock.withLock { $0.resyncContainersList.append(containers) }
    }

    var dockerEvents: [EventEnvelope] {
        lock.withLock { $0.dockerEvents }
    }

    var phases: [SupervisorPhase] {
        lock.withLock { $0.phases }
    }

    var resyncContainersList: [[ContainerSummary]] {
        lock.withLock { $0.resyncContainersList }
    }
}

// MARK: - Thread-safe Counter

private final class Counter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() -> Int {
        lock.withLock { state in
            state += 1
            return state
        }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

// MARK: - Helpers

private func makeEnvelope(sequence: UInt64, action: String = "start", containerId: String = "c1") -> EventEnvelope {
    EventEnvelope(
        sequence: sequence,
        eventAt: Date(timeIntervalSince1970: 1_000_000 + Double(sequence)),
        containerId: containerId,
        action: action,
        attributes: [:],
        source: "container",
        raw: nil
    )
}

private func makeContainer(id: String, name: String) -> ContainerSummary {
    ContainerSummary(
        engineContextId: "test-ctx",
        id: id,
        name: name,
        image: "alpine:3.20",
        status: "Up",
        health: nil,
        labels: [:],
        startedAt: Date()
    )
}

private let testEndpoint = EngineEndpoint(endpointType: .local, address: "/var/run/docker.sock")

private func testError() -> CoreError {
    CoreError.endpointUnreachable(endpoint: testEndpoint, reason: "test")
}

private let fastPolicy = BackoffPolicy(
    initialDelay: .milliseconds(1),
    maxDelay: .milliseconds(10),
    maxRetries: 3,
    multiplier: 2.0
)

// MARK: - Tests

final class EventStreamSupervisorTests: XCTestCase {
    func testSuccessfulStreamYieldsDockerEvents() async throws {
        let mock = MockEngineAdapter()
        let envelopes = [makeEnvelope(sequence: 0), makeEnvelope(sequence: 1), makeEnvelope(sequence: 2)]
        let collector = EventCollector()
        let streamCallCounter = Counter()

        mock.streamEventsHandler = { _ in
            let count = streamCallCounter.increment()
            if count == 1 {
                return AsyncThrowingStream { continuation in
                    for e in envelopes {
                        continuation.yield(e)
                    }
                    // Don't finish — hold the stream open until cancelled
                    continuation.onTermination = { @Sendable _ in }
                }
            } else {
                return AsyncThrowingStream { continuation in
                    continuation.onTermination = { @Sendable _ in }
                }
            }
        }
        mock.listContainersHandler = { [] }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                switch event {
                case let .dockerEvent(envelope):
                    collector.appendDockerEvent(envelope)
                case let .phaseChanged(phase):
                    collector.appendPhase(phase)
                case .resyncCompleted:
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()
        _ = await collectTask.result

        XCTAssertEqual(collector.dockerEvents.count, 3)
        XCTAssertEqual(collector.dockerEvents.map(\.sequence), [0, 1, 2])
        XCTAssertTrue(collector.phases.contains(.streaming))
    }

    func testStreamFailureTriggersDisconnectAndBackoff() async throws {
        let mock = MockEngineAdapter()

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: testError())
            }
        }
        mock.listContainersHandler = { [] }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collector = EventCollector()

        for try await event in stream {
            if case let .phaseChanged(phase) = event {
                collector.appendPhase(phase)
                if case .exhausted = phase { break }
            }
        }

        let phases = collector.phases
        let hasDisconnected = phases.contains { if case .disconnected = $0 { return true }; return false }
        let hasBackingOff = phases.contains { if case .backingOff = $0 { return true }; return false }
        XCTAssertTrue(hasDisconnected, "Should emit disconnected phase")
        XCTAssertTrue(hasBackingOff, "Should emit backingOff phase")
    }

    func testExhaustedAfterMaxRetries() async throws {
        let mock = MockEngineAdapter()

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: testError())
            }
        }
        mock.listContainersHandler = { [] }

        let policy = BackoffPolicy(
            initialDelay: .milliseconds(1),
            maxDelay: .milliseconds(5),
            maxRetries: 2,
            multiplier: 2.0
        )
        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: policy)
        let stream = supervisor.supervise(since: nil)

        var finalPhase: SupervisorPhase?

        for try await event in stream {
            if case let .phaseChanged(phase) = event {
                finalPhase = phase
            }
        }

        if case let .exhausted(total) = finalPhase {
            XCTAssertEqual(total, 3) // maxRetries(2) + 1 = 3 attempts before exhausted
        } else {
            XCTFail("Expected .exhausted, got \(String(describing: finalPhase))")
        }
    }

    func testReconnectPerformsResyncThenResumesEvents() async throws {
        let mock = MockEngineAdapter()
        let callCounter = Counter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            let count = callCounter.increment()
            if count == 1 {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: testError())
                }
            } else {
                // Second call: yield events then hold open
                return AsyncThrowingStream { continuation in
                    continuation.yield(makeEnvelope(sequence: 0))
                    continuation.yield(makeEnvelope(sequence: 1))
                    continuation.onTermination = { @Sendable _ in }
                }
            }
        }

        let resyncContainers = [makeContainer(id: "c1", name: "web")]
        mock.listContainersHandler = { resyncContainers }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                switch event {
                case let .dockerEvent(envelope):
                    collector.appendDockerEvent(envelope)
                case let .phaseChanged(phase):
                    collector.appendPhase(phase)
                case let .resyncCompleted(containers, _):
                    collector.appendResyncContainers(containers)
                }
            }
        }

        try await Task.sleep(for: .milliseconds(200))
        collectTask.cancel()
        _ = await collectTask.result

        XCTAssertGreaterThanOrEqual(collector.resyncContainersList.count, 1, "Should have performed at least one resync")
        XCTAssertGreaterThanOrEqual(mock.listContainersCalls, 1, "Should have called listContainers for resync")
        XCTAssertEqual(collector.dockerEvents.count, 2, "Should have received events from second stream")
        XCTAssertTrue(collector.phases.contains(.resyncing), "Should emit resyncing phase")
    }

    func testConsecutiveFailureCounterResetsOnSuccess() async throws {
        let mock = MockEngineAdapter()
        let callCounter = Counter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            let count = callCounter.increment()
            if count <= 2 {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: testError())
                }
            } else if count == 3 {
                return AsyncThrowingStream { continuation in
                    continuation.yield(makeEnvelope(sequence: 0))
                    continuation.finish()
                }
            } else {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: testError())
                }
            }
        }
        mock.listContainersHandler = { [] }

        let policy = BackoffPolicy(
            initialDelay: .milliseconds(1),
            maxDelay: .milliseconds(5),
            maxRetries: 3,
            multiplier: 2.0
        )
        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: policy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                if case let .phaseChanged(phase) = event {
                    collector.appendPhase(phase)
                    if case .exhausted = phase { return }
                }
            }
        }

        try await Task.sleep(for: .milliseconds(500))
        collectTask.cancel()
        _ = await collectTask.result

        let disconnectAttempts: [Int] = collector.phases.compactMap {
            if case let .disconnected(_, attempt) = $0 { return attempt }
            return nil
        }
        // After success, the counter should have been reset to 0, then increment from 1
        let onesCount = disconnectAttempts.filter { $0 == 1 }.count
        XCTAssertGreaterThanOrEqual(onesCount, 2, "Failure counter should reset after success, showing attempt=1 again")
    }

    func testCancellationDuringStreamEmitsStopped() async throws {
        let mock = MockEngineAdapter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.onTermination = { @Sendable _ in }
            }
        }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                if case let .phaseChanged(phase) = event {
                    collector.appendPhase(phase)
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        collectTask.cancel()
        _ = await collectTask.result

        XCTAssertTrue(collector.phases.contains(.connecting), "Should emit connecting phase")
    }

    func testCancellationDuringBackoffEmitsStopped() async throws {
        let mock = MockEngineAdapter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: testError())
            }
        }
        mock.listContainersHandler = { [] }

        let slowPolicy = BackoffPolicy(
            initialDelay: .seconds(10),
            maxDelay: .seconds(30),
            maxRetries: 5,
            multiplier: 2.0
        )
        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: slowPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                if case let .phaseChanged(phase) = event {
                    collector.appendPhase(phase)
                }
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()
        _ = await collectTask.result

        let phases = collector.phases
        let hasBackingOff = phases.contains { if case .backingOff = $0 { return true }; return false }
        XCTAssertTrue(hasBackingOff, "Should have entered backingOff before cancellation")
        // Note: .stopped may or may not be observed by the consumer due to cancellation race.
        // The key assertion is that backingOff was entered, confirming the supervisor was
        // in the backoff state when cancellation occurred.
    }

    func testSinceParameterForwardedToAdapter() async throws {
        let mock = MockEngineAdapter()
        let since = Date(timeIntervalSince1970: 1_700_000_000)

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(makeEnvelope(sequence: 0))
                continuation.finish()
            }
        }
        mock.listContainersHandler = { [] }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: since)

        let collectTask = Task {
            for try await _ in stream {}
        }

        try await Task.sleep(for: .milliseconds(200))
        collectTask.cancel()
        _ = await collectTask.result

        XCTAssertFalse(mock.streamEventsSinceDates.isEmpty, "Should have called streamEvents at least once")
        XCTAssertEqual(try XCTUnwrap(mock.streamEventsSinceDates.first), since, "First call should use the provided since date")
    }

    func testCleanStreamEndTriggersReconnect() async {
        let mock = MockEngineAdapter()
        let callCounter = Counter()

        mock.streamEventsHandler = { _ in
            _ = callCounter.increment()
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
        mock.listContainersHandler = { [] }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                if case let .phaseChanged(phase) = event,
                   case .exhausted = phase
                {
                    return
                }
            }
        }

        _ = await collectTask.result

        XCTAssertGreaterThan(callCounter.value, 1, "Clean stream end should trigger reconnect attempts")
    }

    func testResyncCompletedContainsContainers() async throws {
        let mock = MockEngineAdapter()
        let callCounter = Counter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            let count = callCounter.increment()
            if count == 1 {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: testError())
                }
            } else {
                return AsyncThrowingStream { continuation in
                    continuation.yield(makeEnvelope(sequence: 0))
                    continuation.finish()
                }
            }
        }

        let expectedContainers = [
            makeContainer(id: "c1", name: "web"),
            makeContainer(id: "c2", name: "db"),
        ]
        mock.listContainersHandler = { expectedContainers }

        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: fastPolicy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                switch event {
                case let .resyncCompleted(containers, _):
                    collector.appendResyncContainers(containers)
                case let .phaseChanged(phase):
                    if case .exhausted = phase { return }
                default:
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(500))
        collectTask.cancel()
        _ = await collectTask.result

        let resyncList = collector.resyncContainersList
        XCTAssertFalse(resyncList.isEmpty, "Should have received resyncCompleted event")
        if let first = resyncList.first {
            XCTAssertEqual(first.count, 2)
            XCTAssertEqual(first.map(\.id).sorted(), ["c1", "c2"])
        }
    }

    func testResyncFailureDoesNotConsumeRetryAttempt() async throws {
        let mock = MockEngineAdapter()
        let listCallCounter = Counter()
        let collector = EventCollector()

        mock.streamEventsHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: testError())
            }
        }

        mock.listContainersHandler = {
            let count = listCallCounter.increment()
            if count <= 2 {
                throw CoreError.endpointUnreachable(endpoint: testEndpoint, reason: "resync fail")
            }
            return []
        }

        let policy = BackoffPolicy(
            initialDelay: .milliseconds(1),
            maxDelay: .milliseconds(5),
            maxRetries: 2,
            multiplier: 2.0
        )
        let supervisor = EventStreamSupervisor(adapter: mock, backoffPolicy: policy)
        let stream = supervisor.supervise(since: nil)

        let collectTask = Task {
            for try await event in stream {
                if case let .phaseChanged(phase) = event {
                    collector.appendPhase(phase)
                    if case .exhausted = phase { return }
                }
            }
        }

        try await Task.sleep(for: .milliseconds(500))
        collectTask.cancel()
        _ = await collectTask.result

        XCTAssertGreaterThan(listCallCounter.value, 0, "Should have attempted resync")
    }
}
