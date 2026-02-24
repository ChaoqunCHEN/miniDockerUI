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
        do {
            try await engine.startContainer(id: id)
            await loadContainers()
        } catch {
            errorMessage = "Failed to start container: \(error.localizedDescription)"
        }
    }

    func stopContainer(id: String) async {
        do {
            try await engine.stopContainer(id: id, timeoutSeconds: nil)
            await loadContainers()
        } catch {
            errorMessage = "Failed to stop container: \(error.localizedDescription)"
        }
    }

    func restartContainer(id: String) async {
        do {
            try await engine.restartContainer(id: id, timeoutSeconds: nil)
            await loadContainers()
        } catch {
            errorMessage = "Failed to restart container: \(error.localizedDescription)"
        }
    }

    // MARK: - Event Stream

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in engine.streamEvents(since: Date()) {
                    await loadContainers()
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Event stream error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }
}
