import Foundation
import MiniDockerCore
import Observation
import os

/// Per-container runtime readiness state tracked by ``ReadinessManager``.
struct ContainerReadinessState: Sendable {
    var result: ReadinessResult?
    var isLatched: Bool = false
    var lastStartedAt: Date?
    var wasRunning: Bool?
    var errorMessage: String?
    var lastContainerId: String?

    /// Reset latch, result, and error — used when a container restarts, recreates, or stops.
    mutating func resetLatch() {
        isLatched = false
        result = nil
        errorMessage = nil
    }
}

private let readinessLogger = Logger(subsystem: "miniDockerUI", category: "ReadinessManager")

/// Centralized manager for container readiness evaluation.
///
/// Owned by ``AppViewModel``, this class:
/// - Persists readiness rules to ``AppSettings`` via ``AppSettingsStore``
/// - Runs background polling for all running containers with rules
/// - Implements latch semantics (once ready, stays ready until restart/stop)
/// - Auto-starts log streams for containers needing regex evaluation
@MainActor
@Observable
final class ReadinessManager {
    private let settingsStore: any AppSettingsStore
    private let engine: any EngineAdapter
    private let logBuffer: LogRingBuffer
    private let evaluator = ReadinessEvaluator()
    /// Readiness rules keyed by container key (engineContextId:name).
    private(set) var rules: [String: ReadinessRule] = [:]

    /// Per-container runtime state keyed by container key.
    private(set) var containerStates: [String: ContainerReadinessState] = [:]

    /// Active polling tasks keyed by container key.
    private var pollingTasks: [String: Task<Void, Never>] = [:]

    /// Active headless log stream tasks keyed by container ID.
    private var headlessLogTasks: [String: Task<Void, Never>] = [:]

    init(
        settingsStore: any AppSettingsStore,
        engine: any EngineAdapter,
        logBuffer: LogRingBuffer
    ) {
        self.settingsStore = settingsStore
        self.engine = engine
        self.logBuffer = logBuffer
        loadRules()
    }

    // MARK: - Rule Persistence

    func saveRule(_ rule: ReadinessRule, forContainerKey key: String) {
        rules[key] = rule
        persistRules()
    }

    func removeRule(forContainerKey key: String) {
        rules.removeValue(forKey: key)
        stopPolling(forContainerKey: key)
        containerStates.removeValue(forKey: key)
        persistRules()
    }

    private func loadRules() {
        do {
            let settings = try settingsStore.load()
            rules = settings.readinessRules
        } catch {
            // Non-fatal: start with empty rules
        }
    }

    private func persistRules() {
        do {
            var settings = try settingsStore.load()
            settings = settings.with(readinessRules: rules)
            try settingsStore.save(settings)
        } catch {
            // Non-fatal: rules will persist on next successful save
        }
    }

    // MARK: - Reconcile

    /// Reconcile readiness state with the current container list.
    /// Called after every `loadContainers()` in ``AppViewModel``.
    ///
    /// Uses a two-phase approach:
    /// 1. Synchronous pass — update state for all containers without awaiting
    /// 2. Async pass — fetch `startedAt` for latched containers to detect restarts,
    ///    re-reading state after each await to avoid clobbering concurrent writes
    func reconcile(containers: [ContainerSummary]) async {
        let containersByKey = Dictionary(
            containers.map { (ContainerGrouper.containerKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Snapshot rules to avoid iterating a live dictionary across
        // suspension points (saveRule/removeRule could mutate it).
        let rulesSnapshot = rules

        // Phase 1: Synchronous state updates, collect latched containers needing inspect.
        var latchedToInspect: [(key: String, containerId: String)] = []

        for key in rulesSnapshot.keys {
            guard let container = containersByKey[key] else {
                // Container gone — stop polling, reset latch
                stopPolling(forContainerKey: key)
                stopHeadlessLogStream(forContainerId: containerStates[key]?.lastContainerId)
                containerStates[key] = ContainerReadinessState()
                continue
            }

            var state = containerStates[key] ?? ContainerReadinessState()

            // Detect state change that should reset the latch:
            // - Container ID changed (docker compose recreate)
            // - Was not running, now running (fresh start after stop)
            let containerIdChanged = state.lastContainerId != nil && state.lastContainerId != container.id
            let freshStart = state.wasRunning == false && container.isRunning

            if containerIdChanged || freshStart {
                state.resetLatch()
                stopPolling(forContainerKey: key)
                stopHeadlessLogStream(forContainerId: state.lastContainerId)
            }

            state.lastContainerId = container.id
            state.wasRunning = container.isRunning

            if container.isRunning, state.isLatched {
                // Needs async startedAt check — collect for phase 2.
                latchedToInspect.append((key: key, containerId: container.id))
            } else if container.isRunning {
                let rule = rulesSnapshot[key]! // Safe: iterating rulesSnapshot.keys
                startPollingIfNeeded(containerKey: key, containerId: container.id, rule: rule)
                startHeadlessLogStreamIfNeeded(containerId: container.id, rule: rule)
            } else {
                // Container stopped — reset latch
                if state.isLatched || state.result != nil {
                    state.resetLatch()
                }
                stopPolling(forContainerKey: key)
                stopHeadlessLogStream(forContainerId: container.id)
            }

            containerStates[key] = state
        }

        // Phase 2: Check startedAt for latched containers to detect restarts.
        // Runs inspect calls concurrently, then processes results with fresh
        // state reads to avoid clobbering concurrent writes.
        if !latchedToInspect.isEmpty {
            let eng = engine
            let timestamps = await withTaskGroup(
                of: (String, String, Date?).self
            ) { group in
                for (key, containerId) in latchedToInspect {
                    group.addTask {
                        do {
                            let detail = try await eng.inspectContainer(id: containerId)
                            return (key, containerId, detail.summary.startedAt)
                        } catch {
                            readinessLogger.debug(
                                "Failed to inspect \(containerId) for startedAt: \(error.localizedDescription)"
                            )
                            return (key, containerId, nil)
                        }
                    }
                }
                var results: [(String, String, Date?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // Process results — re-read state to avoid overwriting concurrent updates.
            for (key, containerId, realStartedAt) in timestamps {
                guard var state = containerStates[key] else { continue }
                // Already unlatched by a concurrent update — nothing to do.
                guard state.isLatched else { continue }

                if let realStartedAt,
                   let prev = state.lastStartedAt,
                   prev != realStartedAt
                {
                    state.resetLatch()
                    state.lastStartedAt = realStartedAt
                    stopPolling(forContainerKey: key)
                    stopHeadlessLogStream(forContainerId: containerId)

                    // Restart polling/headless streams for the now-unlatched container.
                    let rule = rulesSnapshot[key]! // Safe: latchedToInspect only has rulesSnapshot keys
                    startPollingIfNeeded(containerKey: key, containerId: containerId, rule: rule)
                    startHeadlessLogStreamIfNeeded(containerId: containerId, rule: rule)
                    containerStates[key] = state
                }
            }
        }

        // Clean up states for removed rules
        let ruleKeys = Set(rulesSnapshot.keys)
        for key in containerStates.keys where !ruleKeys.contains(key) {
            stopPolling(forContainerKey: key)
            containerStates.removeValue(forKey: key)
        }
    }

    // MARK: - Polling

    func startPollingIfNeeded(containerKey: String, containerId: String, rule: ReadinessRule) {
        guard pollingTasks[containerKey] == nil else { return }
        pollingTasks[containerKey] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.evaluateOnce(containerKey: containerKey, containerId: containerId, rule: rule)

                // If latched, exit the loop. Do NOT self-remove from
                // pollingTasks — reconcile() handles dict cleanup to
                // avoid clobbering a replacement task inserted during await.
                if self.containerStates[containerKey]?.isLatched == true {
                    return
                }

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopPolling(forContainerKey key: String) {
        pollingTasks[key]?.cancel()
        pollingTasks.removeValue(forKey: key)
    }

    func stopAllPolling() {
        pollingTasks.values.forEach { $0.cancel() }
        pollingTasks.removeAll()
        headlessLogTasks.values.forEach { $0.cancel() }
        headlessLogTasks.removeAll()
    }

    /// Whether polling is active for a given container key.
    func isPolling(forContainerKey key: String) -> Bool {
        pollingTasks[key] != nil
    }

    // MARK: - Evaluation

    /// Evaluate readiness once for a container.
    ///
    /// - Parameter force: When `true`, skip the latch check so the evaluation
    ///   runs even if the container is already latched. Used for explicit
    ///   "Test Evaluate" actions from the UI.
    func evaluateOnce(
        containerKey: String,
        containerId: String,
        rule: ReadinessRule,
        force: Bool = false
    ) async {
        // Check latch before expensive async work (skip for forced evaluations).
        if !force, containerStates[containerKey]?.isLatched == true { return }

        do {
            let detail = try await engine.inspectContainer(id: containerId)

            // Re-read state after await to avoid clobbering concurrent updates.
            var state = containerStates[containerKey] ?? ContainerReadinessState()

            // Recheck latch after await (unless forced).
            if !force, state.isLatched { return }

            // Detect restart via the real startedAt from inspect (the list
            // API only exposes createdAt which doesn't change on restart).
            let inspectStartedAt = detail.summary.startedAt
            if let prev = state.lastStartedAt, let cur = inspectStartedAt, prev != cur {
                state.resetLatch()
            }
            if let inspectStartedAt {
                state.lastStartedAt = inspectStartedAt
            }

            let healthStatus = detail.healthDetail?.status
            let logEntries = logBuffer.entries(forContainer: containerId)
            let windowStart = computeWindowStart(
                policy: rule.windowStartPolicy,
                detail: detail,
                logEntries: logEntries
            )

            let result = try evaluator.evaluate(
                rule: rule,
                healthStatus: healthStatus,
                logEntries: logEntries,
                windowStart: windowStart
            )

            state.result = result
            state.errorMessage = nil

            if result.isReady {
                state.isLatched = true
            }

            containerStates[containerKey] = state
        } catch {
            // Re-read state after await for error path too.
            var state = containerStates[containerKey] ?? ContainerReadinessState()
            state.errorMessage = "Evaluation failed: \(error.localizedDescription)"
            containerStates[containerKey] = state
        }
    }

    private func computeWindowStart(
        policy: ReadinessWindowStartPolicy,
        detail: ContainerDetail?,
        logEntries: [LogEntry]
    ) -> Date {
        switch policy {
        case .containerStart:
            return detail?.summary.startedAt ?? Date.distantPast
        case .actionDispatch:
            return Date()
        case .firstLogEntry:
            return logEntries.first?.timestamp ?? Date.distantPast
        }
    }

    // MARK: - Headless Log Streaming

    /// Start a lightweight log stream for regex evaluation if the log buffer is empty.
    private func startHeadlessLogStreamIfNeeded(containerId: String, rule: ReadinessRule) {
        // Only needed for regex-based rules (regexOnly or healthThenRegex)
        guard rule.mode != .healthOnly else { return }
        guard headlessLogTasks[containerId] == nil else { return }

        // Only start if the buffer is empty for this container
        let existingCount = logBuffer.lineCount(forContainer: containerId)
        guard existingCount == 0 else { return }

        headlessLogTasks[containerId] = Task { [weak self] in
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
                for try await entry in self.engine.streamLogs(id: containerId, options: options) {
                    self.logBuffer.append(entry)
                }
            } catch {
                // Stream ended or cancelled — clean up
            }
            // Do NOT self-remove from headlessLogTasks. reconcile() and
            // stopHeadlessLogStream() handle dict cleanup to avoid
            // clobbering a replacement task inserted during the stream.
        }
    }

    private func stopHeadlessLogStream(forContainerId id: String?) {
        guard let id else { return }
        headlessLogTasks[id]?.cancel()
        headlessLogTasks.removeValue(forKey: id)
    }

    // MARK: - Display

    /// Returns a readiness display string for the sidebar.
    /// - `nil` → no rule configured (show default status)
    /// - `"-"` → rule exists, not ready yet
    /// - `"Ready"` → latched ready
    func readinessDisplay(for container: ContainerSummary) -> String? {
        let key = ContainerGrouper.containerKey(for: container)
        guard rules[key] != nil else { return nil }
        guard container.isRunning else { return nil }

        let state = containerStates[key]
        if state?.isLatched == true {
            return "Ready"
        }
        return "-"
    }
}
