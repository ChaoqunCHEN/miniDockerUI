import Foundation
import MiniDockerCore
import os

final class MockEngineAdapter: EngineAdapter, @unchecked Sendable {
    struct State {
        var containers: [ContainerSummary] = []
        var containerDetails: [String: ContainerDetail] = [:]
        var startedIds: [String] = []
        var stoppedIds: [String] = []
        var restartedIds: [String] = []
        var shouldThrowOnStart: Bool = false
        var shouldThrowOnStop: Bool = false
        var shouldThrowOnRestart: Bool = false
        var shouldThrowOnInspect: Bool = false
        var shouldThrowOnList: Bool = false
        var logEntries: [String: [LogEntry]] = [:]
    }

    private let state: OSAllocatedUnfairLock<State>

    init(state: State = State()) {
        self.state = OSAllocatedUnfairLock(initialState: state)
    }

    var startedIds: [String] {
        state.withLock { $0.startedIds }
    }

    var stoppedIds: [String] {
        state.withLock { $0.stoppedIds }
    }

    var restartedIds: [String] {
        state.withLock { $0.restartedIds }
    }

    func setContainers(_ containers: [ContainerSummary]) {
        state.withLock { $0.containers = containers }
    }

    func setContainerDetail(_ detail: ContainerDetail, forId id: String) {
        state.withLock { $0.containerDetails[id] = detail }
    }

    func setLogEntries(_ entries: [LogEntry], forContainer id: String) {
        state.withLock { $0.logEntries[id] = entries }
    }

    func setShouldThrowOnStart(_ value: Bool) {
        state.withLock { $0.shouldThrowOnStart = value }
    }

    func setShouldThrowOnStop(_ value: Bool) {
        state.withLock { $0.shouldThrowOnStop = value }
    }

    func setShouldThrowOnRestart(_ value: Bool) {
        state.withLock { $0.shouldThrowOnRestart = value }
    }

    func setShouldThrowOnInspect(_ value: Bool) {
        state.withLock { $0.shouldThrowOnInspect = value }
    }

    func setShouldThrowOnList(_ value: Bool) {
        state.withLock { $0.shouldThrowOnList = value }
    }

    // MARK: - EngineAdapter

    func listContainers() async throws -> [ContainerSummary] {
        try state.withLock { s in
            if s.shouldThrowOnList {
                throw CoreError.endpointUnreachable(
                    endpoint: EngineEndpoint(endpointType: .local, address: "mock"),
                    reason: "mock error"
                )
            }
            return s.containers
        }
    }

    func inspectContainer(id: String) async throws -> ContainerDetail {
        try state.withLock { s in
            if s.shouldThrowOnInspect {
                throw CoreError.endpointUnreachable(
                    endpoint: EngineEndpoint(endpointType: .local, address: "mock"),
                    reason: "mock inspect error"
                )
            }
            guard let detail = s.containerDetails[id] else {
                throw CoreError.contractViolation(
                    expected: "container detail for \(id)",
                    actual: "not found"
                )
            }
            return detail
        }
    }

    func startContainer(id: String) async throws {
        try state.withLock { s in
            if s.shouldThrowOnStart {
                throw CoreError.processNonZeroExit(
                    executablePath: "docker",
                    exitCode: 1,
                    stderr: "mock start error"
                )
            }
            s.startedIds.append(id)
        }
    }

    func stopContainer(id: String, timeoutSeconds _: Int?) async throws {
        try state.withLock { s in
            if s.shouldThrowOnStop {
                throw CoreError.processNonZeroExit(
                    executablePath: "docker",
                    exitCode: 1,
                    stderr: "mock stop error"
                )
            }
            s.stoppedIds.append(id)
        }
    }

    func restartContainer(id: String, timeoutSeconds _: Int?) async throws {
        try state.withLock { s in
            if s.shouldThrowOnRestart {
                throw CoreError.processNonZeroExit(
                    executablePath: "docker",
                    exitCode: 1,
                    stderr: "mock restart error"
                )
            }
            s.restartedIds.append(id)
        }
    }

    func streamEvents(since _: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func streamLogs(id: String, options _: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        let entries = state.withLock { $0.logEntries[id] ?? [] }
        return AsyncThrowingStream { continuation in
            for entry in entries {
                continuation.yield(entry)
            }
            continuation.finish()
        }
    }
}
