import MiniDockerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ContainerDetailViewModel {
    let engine: any EngineAdapter
    let containerId: String
    let logBuffer: LogRingBuffer
    let readinessManager: ReadinessManager
    let containerKey: String

    var detail: ContainerDetail?
    var displayEntries: [LogEntry] = []
    var isLoadingDetail: Bool = false
    var isStreamingLogs: Bool = false
    var errorMessage: String?
    var healthStatus: ContainerHealthStatus?

    private var logStreamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var logsSince: Date?
    private var _readinessViewModel: ReadinessViewModel?

    /// Cached readiness view model — created once per container detail session
    /// to avoid discarding editing state on every SwiftUI body re-evaluation.
    var readinessViewModel: ReadinessViewModel {
        if let existing = _readinessViewModel {
            return existing
        }
        let vm = ReadinessViewModel(
            readinessManager: readinessManager,
            containerId: containerId,
            containerKey: containerKey
        )
        _readinessViewModel = vm
        return vm
    }

    init(
        engine: any EngineAdapter,
        containerId: String,
        logBuffer: LogRingBuffer,
        readinessManager: ReadinessManager,
        containerKey: String
    ) {
        self.engine = engine
        self.containerId = containerId
        self.logBuffer = logBuffer
        self.readinessManager = readinessManager
        self.containerKey = containerKey
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
        logBuffer.clear(containerId: containerId)
        displayEntries.removeAll()
        logsSince = Date()
        startLogStream()
    }

    // MARK: - Detail

    func loadDetail() async {
        isLoadingDetail = true
        errorMessage = nil
        do {
            detail = try await engine.inspectContainer(id: containerId)
            healthStatus = detail?.healthDetail?.status
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
                    logBuffer.append(entry)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Log stream error: \(error.localizedDescription)"
                }
            }
            // Stream ended (container stopped or connection lost) -- clean up
            // so startLogStream() can be called again
            logStreamTask = nil
            isStreamingLogs = false
        }
        startFlushTimer()
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        stopFlushTimer()
        isStreamingLogs = false
    }

    func clearLogs() {
        restartLogStream()
    }

    // MARK: - Flush Timer (~30 Hz)

    private func startFlushTimer() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
                guard let self else { return }
                displayEntries = logBuffer.entries(forContainer: containerId)
            }
        }
    }

    private func stopFlushTimer() {
        flushTask?.cancel()
        flushTask = nil
    }
}
