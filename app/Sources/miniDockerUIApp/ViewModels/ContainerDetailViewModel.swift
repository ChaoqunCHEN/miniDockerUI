import MiniDockerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ContainerDetailViewModel {
    private let engine: any EngineAdapter
    let containerId: String

    var detail: ContainerDetail?
    var logEntries: [LogEntry] = []
    var isLoadingDetail: Bool = false
    var isStreamingLogs: Bool = false
    var errorMessage: String?

    private var logStreamTask: Task<Void, Never>?
    private let maxLogEntries = 5000
    private var logsSince: Date?

    init(engine: any EngineAdapter, containerId: String) {
        self.engine = engine
        self.containerId = containerId
    }

    // MARK: - Actions

    func startContainer() async {
        let success = await performAction("start") {
            try await engine.startContainer(id: containerId)
        }
        if success { restartLogStream() }
    }

    func stopContainer() async {
        await performAction("stop") {
            try await engine.stopContainer(id: containerId, timeoutSeconds: nil)
        }
    }

    func restartContainer() async {
        let success = await performAction("restart") {
            try await engine.restartContainer(id: containerId, timeoutSeconds: nil)
        }
        if success { restartLogStream() }
    }

    @discardableResult
    private func performAction(_ label: String, action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            await loadDetail()
            return true
        } catch {
            errorMessage = "Failed to \(label): \(error.localizedDescription)"
            return false
        }
    }

    private func restartLogStream() {
        stopLogStream()
        logEntries.removeAll()
        logsSince = Date()
        startLogStream()
    }

    // MARK: - Detail

    func loadDetail() async {
        isLoadingDetail = true
        errorMessage = nil
        do {
            detail = try await engine.inspectContainer(id: containerId)
        } catch {
            errorMessage = "Failed to inspect container: \(error.localizedDescription)"
        }
        isLoadingDetail = false
    }

    // MARK: - Log Streaming

    func startLogStream() {
        guard logStreamTask == nil else { return }
        isStreamingLogs = true
        let since = logsSince
        logStreamTask = Task { [weak self] in
            guard let self else { return }
            let options = LogStreamOptions(
                since: since,
                tail: since == nil ? 200 : 0,
                includeStdout: true,
                includeStderr: true,
                timestamps: true,
                follow: true
            )
            do {
                for try await entry in engine.streamLogs(id: containerId, options: options) {
                    logEntries.append(entry)
                    if logEntries.count > maxLogEntries {
                        logEntries.removeFirst(logEntries.count - maxLogEntries)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Log stream error: \(error.localizedDescription)"
                }
            }
            // Stream ended (container stopped or connection lost) — clean up
            // so startLogStream() can be called again
            logStreamTask = nil
            isStreamingLogs = false
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
    }

    func clearLogs() {
        restartLogStream()
    }
}
