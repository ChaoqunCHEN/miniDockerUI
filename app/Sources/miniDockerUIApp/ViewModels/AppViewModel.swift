import MiniDockerCore
import Observation
import SwiftUI

struct AppError: Equatable {
    let id: UUID
    let message: String
    let isPersistent: Bool

    static func transient(_ message: String) -> AppError {
        AppError(id: UUID(), message: message, isPersistent: false)
    }

    static func persistent(_ message: String) -> AppError {
        AppError(id: UUID(), message: message, isPersistent: true)
    }
}

@MainActor
@Observable
final class AppViewModel {
    let engine: any EngineAdapter
    let settingsStore: any AppSettingsStore
    let logBuffer: LogRingBuffer
    let composeExecutor: any ComposeExecutor
    let worktreeViewModel: ComposeWorktreeViewModel
    let readinessManager: ReadinessManager

    var containers: [ContainerSummary] = []
    var selectedContainerId: String?
    var isLoading: Bool = false
    var currentError: AppError?
    var favoriteKeys: Set<String> = []
    var actionInProgress: [String: ContainerAction] = [:]

    private var eventStreamTask: Task<Void, Never>?
    private var pendingReloadTask: Task<Void, Never>?
    private var detailViewModels: [String: ContainerDetailViewModel] = [:]

    init(
        engine: any EngineAdapter,
        settingsStore: any AppSettingsStore,
        logBuffer: LogRingBuffer,
        composeExecutor: any ComposeExecutor,
        worktreeViewModel: ComposeWorktreeViewModel
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.logBuffer = logBuffer
        self.composeExecutor = composeExecutor
        self.worktreeViewModel = worktreeViewModel
        readinessManager = ReadinessManager(
            settingsStore: settingsStore,
            engine: engine,
            logBuffer: logBuffer
        )
        loadFavorites()
    }

    // MARK: - Detail ViewModel Cache

    func detailViewModel(for containerId: String) -> ContainerDetailViewModel {
        if let existing = detailViewModels[containerId] {
            return existing
        }
        let container = containers.first { $0.id == containerId }
        let key = container.map { self.containerKey(for: $0) } ?? ""
        let vm = ContainerDetailViewModel(
            engine: engine,
            containerId: containerId,
            logBuffer: logBuffer,
            readinessManager: readinessManager,
            containerKey: key
        )
        detailViewModels[containerId] = vm
        return vm
    }

    // MARK: - Favorites

    func containerKey(for container: ContainerSummary) -> String {
        ContainerGrouper.containerKey(for: container)
    }

    func isFavorite(_ container: ContainerSummary) -> Bool {
        favoriteKeys.contains(containerKey(for: container))
    }

    func toggleFavorite(for container: ContainerSummary) {
        let key = containerKey(for: container)
        if favoriteKeys.contains(key) {
            favoriteKeys.remove(key)
        } else {
            favoriteKeys.insert(key)
        }
        saveFavorites()
    }

    private func loadFavorites() {
        do {
            let settings = try settingsStore.load()
            favoriteKeys = settings.favoriteContainerKeys
        } catch {
            currentError = .transient("Failed to load settings: \(error.localizedDescription)")
        }
    }

    private func saveFavorites() {
        do {
            var settings = try settingsStore.load()
            settings = settings.with(favoriteContainerKeys: favoriteKeys)
            try settingsStore.save(settings)
        } catch {
            currentError = .transient("Failed to save favorites: \(error.localizedDescription)")
        }
    }

    // MARK: - Container List

    func loadContainers() async {
        isLoading = true
        do {
            containers = try await engine.listContainers()
            evictStaleDetailViewModels()
            await worktreeViewModel.detectAndLoadWorktrees(from: containers)
            await readinessManager.reconcile(containers: containers)
            currentError = nil
        } catch {
            if !Task.isCancelled {
                currentError = .persistent(
                    "Failed to list containers: \(error.localizedDescription)"
                )
            }
        }
        isLoading = false
    }

    private func evictStaleDetailViewModels() {
        let liveIds = Set(containers.map(\.id))
        for (id, vm) in detailViewModels where !liveIds.contains(id) {
            vm.stopLogStream()
            detailViewModels.removeValue(forKey: id)
        }
    }

    // MARK: - Container Actions

    func startContainer(id: String) async {
        await performContainerAction(id: id, action: .start) {
            try await engine.startContainer(id: id)
        }
    }

    func stopContainer(id: String) async {
        await performContainerAction(id: id, action: .stop) {
            try await engine.stopContainer(id: id, timeoutSeconds: nil)
        }
    }

    func restartContainer(id: String) async {
        if let worktreeRestart = worktreeRestartParams(for: id) {
            // Recreate through docker compose so the worktree directory switch
            // takes effect. Config files are omitted so compose auto-discovers
            // from the new --project-directory.
            await performContainerAction(id: id, action: .restart) {
                try await composeExecutor.recreateService(
                    projectName: worktreeRestart.projectName,
                    projectDirectory: worktreeRestart.directory,
                    configFiles: [],
                    serviceName: worktreeRestart.serviceName,
                    timeoutSeconds: nil
                )
            }
        } else {
            await performContainerAction(id: id, action: .restart) {
                try await engine.restartContainer(id: id, timeoutSeconds: nil)
            }
        }
    }

    private func performContainerAction(
        id: String,
        action: ContainerAction,
        operation: () async throws -> Void
    ) async {
        actionInProgress[id] = action
        defer { actionInProgress.removeValue(forKey: id) }
        do {
            try await operation()
            await loadContainers()
        } catch {
            currentError = .transient(
                "Failed to \(action.rawValue) container: \(error.localizedDescription)"
            )
        }
    }

    private func worktreeRestartParams(for containerId: String) -> (projectName: String, directory: String, serviceName: String)? {
        guard let directory = worktreeViewModel.selectedWorktreeDirectory(for: containerId),
              let project = worktreeViewModel.projectForContainer(containerId),
              let container = containers.first(where: { $0.id == containerId }),
              let serviceName = container.labels[ComposeProjectDetector.serviceLabelKey]
        else {
            return nil
        }
        return (project.projectName, directory, serviceName)
    }

    // MARK: - Event Stream

    /// Debounce event-driven reloads so bursts of Docker events
    /// (e.g. start + attach + connect) collapse into a single reload.
    private func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadContainers()
        }
    }

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            defer { self?.eventStreamTask = nil }

            var retryDelay: Duration = .seconds(1)
            let maxDelay: Duration = .seconds(30)
            var consecutiveFailures = 0
            let maxRetries = 10

            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await _ in engine.streamEvents(since: Date()) {
                        scheduleReload()
                    }
                    // Stream ended cleanly -- reset backoff and reconnect immediately
                    retryDelay = .seconds(1)
                    consecutiveFailures = 0
                } catch {
                    if Task.isCancelled { return }
                    consecutiveFailures += 1
                    if consecutiveFailures >= maxRetries {
                        currentError = .persistent(
                            "Docker event stream unreachable after \(maxRetries) retries. Press Retry to reconnect."
                        )
                        return
                    }
                    currentError = .transient(
                        "Event stream error: \(error.localizedDescription)"
                    )
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, maxDelay)
                }
            }
        }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        readinessManager.stopAllPolling()
    }

    /// Stop the event stream, reload containers, and restart the event stream.
    /// Used as the retry action for persistent errors and the refresh button handler.
    func refreshAndReconnect() async {
        let oldTask = eventStreamTask
        stopEventStream()
        // Await the old task to ensure it fully exits before restarting,
        // preventing overlap between old and new event stream tasks.
        await oldTask?.value
        await loadContainers()
        startEventStream()
    }
}
