import Foundation
@testable import MiniDockerCore
import os
import XCTest

// MARK: - Thread-Safe Mock Command Runner

/// A command runner that records invocations and returns canned results.
/// Handlers are set during test setup (single-threaded); captured requests
/// are protected by a lock for concurrent access.
final class ScenarioMockCommandRunner: CommandRunning, @unchecked Sendable {
    var runHandler: ((CommandRequest) async throws -> CommandResult)?
    var runCheckedHandler: ((CommandRequest) async throws -> CommandResult)?
    var streamHandler: ((CommandRequest) -> AsyncThrowingStream<Data, Error>)?

    private let lock = OSAllocatedUnfairLock(initialState: CapturedState())

    struct CapturedState: Sendable {
        var capturedRunRequests: [CommandRequest] = []
        var capturedRunCheckedRequests: [CommandRequest] = []
        var capturedStreamRequests: [CommandRequest] = []
    }

    // MARK: - Captured Requests

    var capturedRunRequests: [CommandRequest] {
        lock.withLock { $0.capturedRunRequests }
    }

    var capturedRunCheckedRequests: [CommandRequest] {
        lock.withLock { $0.capturedRunCheckedRequests }
    }

    var capturedStreamRequests: [CommandRequest] {
        lock.withLock { $0.capturedStreamRequests }
    }

    // MARK: - CommandRunning Conformance

    func run(_ request: CommandRequest) async throws -> CommandResult {
        lock.withLock { $0.capturedRunRequests.append(request) }
        guard let handler = runHandler else {
            return CommandResult(exitCode: 0)
        }
        return try await handler(request)
    }

    func runChecked(_ request: CommandRequest) async throws -> CommandResult {
        lock.withLock { $0.capturedRunCheckedRequests.append(request) }
        guard let handler = runCheckedHandler else {
            return CommandResult(exitCode: 0)
        }
        return try await handler(request)
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        lock.withLock { $0.capturedStreamRequests.append(request) }
        guard let handler = streamHandler else {
            return AsyncThrowingStream { $0.finish() }
        }
        return handler(request)
    }
}

// MARK: - Deterministic Log Entry Factory

enum LogEntryFactory {
    static func makeEntry(
        containerId: String = "test-container",
        message: String,
        timestamp: Date = Date(),
        stream: LogStream = .stdout,
        engineContextId: String = "integ-ctx"
    ) -> LogEntry {
        LogEntry(
            engineContextId: engineContextId,
            containerId: containerId,
            stream: stream,
            timestamp: timestamp,
            message: message
        )
    }

    static func makeBatch(
        containerId: String = "test-container",
        count: Int,
        bytesPerLine: Int = 80,
        startTimestamp: Date = Date(timeIntervalSince1970: 1_000_000),
        intervalSeconds: Double = 0.001
    ) -> [LogEntry] {
        let padding = String(repeating: "x", count: max(0, bytesPerLine - 20))
        return (0 ..< count).map { i in
            LogEntry(
                engineContextId: "integ-ctx",
                containerId: containerId,
                stream: .stdout,
                timestamp: startTimestamp.addingTimeInterval(Double(i) * intervalSeconds),
                message: "line-\(String(format: "%06d", i))-\(padding)"
            )
        }
    }
}

// MARK: - Test Utilities

func skipUnlessDockerAvailable() throws {
    try XCTSkipUnless(
        FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
        "Docker not available"
    )
}

func sleepDescriptor(key: String, image: String = "alpine:3.20") -> FixtureDescriptor {
    FixtureDescriptor(
        key: key,
        image: image,
        command: ["sleep", "3600"],
        environment: [:]
    )
}

// MARK: - Container Summary Factory

enum ContainerSummaryFactory {
    static func make(
        id: String,
        name: String = "test",
        image: String = "alpine:3.20",
        status: String = "Up",
        health: ContainerHealthStatus? = nil,
        engineContextId: String = "integ-ctx"
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: engineContextId,
            id: id,
            name: name,
            image: image,
            status: status,
            health: health,
            labels: [:],
            startedAt: nil
        )
    }
}

// MARK: - Event Envelope Factory

enum EventEnvelopeFactory {
    static func make(
        sequence: UInt64,
        containerId: String? = "test-container",
        action: String = "start",
        attributes: [String: String] = [:],
        eventAt: Date = Date()
    ) -> EventEnvelope {
        EventEnvelope(
            sequence: sequence,
            eventAt: eventAt,
            containerId: containerId,
            action: action,
            attributes: attributes,
            source: "test",
            raw: nil
        )
    }
}
