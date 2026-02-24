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

    init(engine: any EngineAdapter, containerId: String) {
        self.engine = engine
        self.containerId = containerId
    }

    // MARK: - Actions

    func startContainer() async {
        do {
            try await engine.startContainer(id: containerId)
            await loadDetail()
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
        }
    }

    func stopContainer() async {
        do {
            try await engine.stopContainer(id: containerId, timeoutSeconds: nil)
            await loadDetail()
        } catch {
            errorMessage = "Failed to stop: \(error.localizedDescription)"
        }
    }

    func restartContainer() async {
        do {
            try await engine.restartContainer(id: containerId, timeoutSeconds: nil)
            await loadDetail()
        } catch {
            errorMessage = "Failed to restart: \(error.localizedDescription)"
        }
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
        logStreamTask = Task { [weak self] in
            guard let self else { return }
            let options = LogStreamOptions(
                since: nil,
                tail: 200,
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
            isStreamingLogs = false
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
    }
}
