import MiniDockerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    let engine: any EngineAdapter
    let settingsStore: any AppSettingsStore
    let logBuffer: LogRingBuffer

    var containers: [ContainerSummary] = []
    var selectedContainerId: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var favoriteKeys: Set<String> = []
    var actionInProgress: [String: ContainerAction] = [:]

    private var eventStreamTask: Task<Void, Never>?
    private var detailViewModels: [String: ContainerDetailViewModel] = [:]

    init(engine: any EngineAdapter, settingsStore: any AppSettingsStore, logBuffer: LogRingBuffer) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.logBuffer = logBuffer
        loadFavorites()
    }

    // MARK: - Detail ViewModel Cache

    func detailViewModel(for containerId: String) -> ContainerDetailViewModel {
        if let existing = detailViewModels[containerId] {
            return existing
        }
        let vm = ContainerDetailViewModel(
            engine: engine,
            containerId: containerId,
            logBuffer: logBuffer
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
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    private func saveFavorites() {
        do {
            var settings = try settingsStore.load()
            settings = settings.with(favoriteContainerKeys: favoriteKeys)
            try settingsStore.save(settings)
        } catch {
            errorMessage = "Failed to save favorites: \(error.localizedDescription)"
        }
    }

    // MARK: - Container List

    func loadContainers() async {
        isLoading = true
        errorMessage = nil
        do {
            containers = try await engine.listContainers()
            evictStaleDetailViewModels()
        } catch {
            errorMessage = "Failed to list containers: \(error.localizedDescription)"
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
        await performContainerAction(id: id, action: .restart) {
            try await engine.restartContainer(id: id, timeoutSeconds: nil)
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
            errorMessage = "Failed to \(action.rawValue) container: \(error.localizedDescription)"
        }
    }

    // MARK: - Event Stream

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            var retryDelay: UInt64 = 1_000_000_000 // 1 second
            let maxDelay: UInt64 = 30_000_000_000 // 30 seconds
            var consecutiveFailures = 0
            let maxRetries = 10

            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await _ in engine.streamEvents(since: Date()) {
                        await loadContainers()
                    }
                    // Stream ended cleanly — reset backoff and reconnect immediately
                    retryDelay = 1_000_000_000
                    consecutiveFailures = 0
                } catch {
                    if Task.isCancelled { return }
                    consecutiveFailures += 1
                    if consecutiveFailures >= maxRetries {
                        errorMessage = "Docker event stream unreachable after \(maxRetries) retries. Use Refresh to reconnect."
                        return
                    }
                    errorMessage = "Event stream error: \(error.localizedDescription)"
                    try? await Task.sleep(nanoseconds: retryDelay)
                    retryDelay = min(retryDelay * 2, maxDelay)
                }
            }
        }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }
}
