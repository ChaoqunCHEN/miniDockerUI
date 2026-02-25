import MiniDockerCore
import Observation

@MainActor
@Observable
final class WorktreeSwitchViewModel {
    private let planner: WorktreeSwitchPlanner
    private let engine: any EngineAdapter
    private let settingsStore: any AppSettingsStore

    var mappings: [WorktreeMapping] = []
    var selectedMappingId: String?
    var fromWorktree: String = ""
    var toWorktree: String = ""
    var switchPlan: WorktreeSwitchPlan?
    var isSwitching: Bool = false
    var switchProgress: WorktreeSwitchProgress = .idle
    var errorMessage: String?

    enum WorktreeSwitchProgress: Equatable {
        case idle
        case planning
        case restarting(containerId: String)
        case verifyingReadiness
        case completed
        case failed(String)
    }

    init(
        engine: any EngineAdapter,
        settingsStore: any AppSettingsStore,
        planner: WorktreeSwitchPlanner = WorktreeSwitchPlanner()
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.planner = planner
    }

    // MARK: - Load Mappings

    func loadMappings() {
        errorMessage = nil
        do {
            let settings = try settingsStore.load()
            mappings = settings.worktreeMappings
        } catch {
            errorMessage = "Failed to load mappings: \(error.localizedDescription)"
        }
    }

    // MARK: - Plan Switch

    func planSwitch() async {
        guard let mappingId = selectedMappingId,
              let mapping = mappings.first(where: { $0.id == mappingId })
        else {
            errorMessage = "No mapping selected"
            return
        }

        switchProgress = .planning
        errorMessage = nil

        do {
            let settings = try settingsStore.load()
            let readinessRule = settings.readinessRules[mappingId] ?? ReadinessRule(
                mode: .healthOnly,
                regexPattern: nil,
                mustMatchCount: 1,
                windowStartPolicy: .containerStart
            )

            let containers = try await engine.listContainers()
            let runningIds = Set(containers.filter(\.isRunning).map(\.id))

            switchPlan = try planner.planSwitch(
                mapping: mapping,
                fromWorktree: fromWorktree,
                toWorktree: toWorktree,
                readinessRule: readinessRule,
                runningContainerIds: runningIds
            )
        } catch {
            switchProgress = .failed(error.localizedDescription)
            errorMessage = "Planning failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Execute Switch

    func executeSwitch() async {
        guard let plan = switchPlan else {
            errorMessage = "No switch plan available"
            return
        }

        isSwitching = true
        errorMessage = nil

        for targetId in plan.restartTargets {
            switchProgress = .restarting(containerId: targetId)
            do {
                try await engine.restartContainer(id: targetId, timeoutSeconds: nil)
            } catch {
                switchProgress = .failed("Failed to restart \(targetId): \(error.localizedDescription)")
                errorMessage = "Restart failed: \(error.localizedDescription)"
                isSwitching = false
                return
            }
        }

        switchProgress = .verifyingReadiness
        // Readiness verification is handled by ReadinessViewModel externally;
        // mark as completed after restarts finish.
        switchProgress = .completed
        isSwitching = false
    }
}
