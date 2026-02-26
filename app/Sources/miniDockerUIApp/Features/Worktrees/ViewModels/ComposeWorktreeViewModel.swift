import MiniDockerCore
import Observation

/// Manages worktree state for detected Docker Compose projects.
///
/// Auto-detects compose projects from container labels, discovers
/// git worktrees for each project, and tracks user-selected worktree
/// per project. The ``selectedWorktreeDirectory(for:)`` method is
/// called by ``AppViewModel`` during restart to decide whether to
/// use compose recreation instead of a simple `docker restart`.
@MainActor
@Observable
final class ComposeWorktreeViewModel {
    private let gitAdapter: any GitAdapter
    private let detector: ComposeProjectDetector

    // MARK: - Published State

    /// Detected compose projects from container labels.
    var detectedProjects: [ComposeProject] = []

    /// Available git worktrees per project (keyed by projectName).
    var projectWorktrees: [String: [GitWorktreeInfo]] = [:]

    /// User-selected worktree path per project (keyed by projectName).
    /// When the user picks a different worktree, this is updated.
    var selectedWorktrees: [String: String] = [:]

    /// Whether detection/loading is in progress.
    var isLoading: Bool = false

    /// Error message from last operation.
    var errorMessage: String?

    /// Fingerprint of the last set of projects we ran git operations for.
    /// Format: sorted "name:workingDir" pairs joined by newline.
    private var lastProjectFingerprint: String = ""

    init(gitAdapter: any GitAdapter) {
        self.gitAdapter = gitAdapter
        detector = ComposeProjectDetector()
    }

    // MARK: - Detection

    /// Detect compose projects from the current container list and
    /// load git worktrees for each project.
    ///
    /// Git operations are skipped if the detected projects have not
    /// changed since the last call (same project names and working
    /// directories), avoiding redundant shell-outs on every Docker
    /// event.
    func detectAndLoadWorktrees(from containers: [ContainerSummary]) async {
        let projects = detector.detectProjects(from: containers)
        detectedProjects = projects

        let fingerprint = projectFingerprint(for: projects)
        guard fingerprint != lastProjectFingerprint else { return }

        isLoading = true
        defer { isLoading = false }

        var newWorktrees: [String: [GitWorktreeInfo]] = [:]
        for project in projects {
            guard !project.workingDirectory.isEmpty else { continue }
            do {
                let repoRoot = try await gitAdapter.repoRoot(for: project.workingDirectory)
                let worktrees = try await gitAdapter.listWorktrees(repoRoot: repoRoot)
                newWorktrees[project.projectName] = worktrees
            } catch {
                continue
            }
        }
        projectWorktrees = newWorktrees
        lastProjectFingerprint = fingerprint

        // Clean up selections for projects that no longer exist.
        let validProjectNames = Set(projects.map(\.projectName))
        for key in selectedWorktrees.keys where !validProjectNames.contains(key) {
            selectedWorktrees.removeValue(forKey: key)
        }
    }

    /// Stable fingerprint for a set of projects based on names and working dirs.
    private func projectFingerprint(for projects: [ComposeProject]) -> String {
        projects
            .map { "\($0.projectName):\($0.workingDirectory)" }
            .sorted()
            .joined(separator: "\n")
    }

    // MARK: - Selection

    /// Returns the selected worktree directory for the given container's
    /// compose project, but **only** if it differs from the project's
    /// current working directory. Returns nil if no switch is needed.
    func selectedWorktreeDirectory(for containerId: String) -> String? {
        guard let project = projectForContainer(containerId),
              let selected = selectedWorktrees[project.projectName],
              !selected.isEmpty,
              selected != project.workingDirectory
        else {
            return nil
        }
        return selected
    }

    /// Returns the compose project that a container belongs to, if any.
    func projectForContainer(_ containerId: String) -> ComposeProject? {
        detectedProjects.first { $0.containerIds.contains(containerId) }
    }

    /// Whether any project has a pending worktree change.
    var hasPendingChanges: Bool {
        detectedProjects.contains { project in
            guard let selected = selectedWorktrees[project.projectName] else { return false }
            return !selected.isEmpty && selected != project.workingDirectory
        }
    }
}
