import MiniDockerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    let engine: any EngineAdapter

    var containers: [ContainerSummary] = []
    var selectedContainerId: String?
    var isLoading: Bool = false
    var errorMessage: String?

    private var eventStreamTask: Task<Void, Never>?

    init(engine: any EngineAdapter) {
        self.engine = engine
    }

    // MARK: - Container List

    func loadContainers() async {
        isLoading = true
        errorMessage = nil
        do {
            containers = try await engine.listContainers()
        } catch {
            errorMessage = "Failed to list containers: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Container Actions

    func startContainer(id: String) async {
        await performAction("start container") {
            try await engine.startContainer(id: id)
        }
    }

    func stopContainer(id: String) async {
        await performAction("stop container") {
            try await engine.stopContainer(id: id, timeoutSeconds: nil)
        }
    }

    func restartContainer(id: String) async {
        await performAction("restart container") {
            try await engine.restartContainer(id: id, timeoutSeconds: nil)
        }
    }

    private func performAction(_ label: String, action: () async throws -> Void) async {
        do {
            try await action()
            await loadContainers()
        } catch {
            errorMessage = "Failed to \(label): \(error.localizedDescription)"
        }
    }

    // MARK: - Event Stream

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            var retryDelay: UInt64 = 1_000_000_000 // 1 second
            let maxDelay: UInt64 = 30_000_000_000 // 30 seconds

            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await _ in engine.streamEvents(since: Date()) {
                        retryDelay = 1_000_000_000
                        await loadContainers()
                    }
                    // Stream ended cleanly, reconnect after delay
                } catch {
                    if Task.isCancelled { return }
                    errorMessage = "Event stream error: \(error.localizedDescription)"
                }
                try? await Task.sleep(nanoseconds: retryDelay)
                retryDelay = min(retryDelay * 2, maxDelay)
            }
        }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }
}
