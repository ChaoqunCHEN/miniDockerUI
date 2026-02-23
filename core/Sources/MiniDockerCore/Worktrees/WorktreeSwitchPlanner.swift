import Foundation

/// Pure function layer for generating ``WorktreeSwitchPlan`` instances.
///
/// Validates switch parameters and computes restart targets based on policy.
/// No filesystem or Docker access — the caller provides runtime state.
public struct WorktreeSwitchPlanner: Sendable {
    public init() {}

    /// Generate a switch plan from a validated mapping.
    ///
    /// - Parameters:
    ///   - mapping: A validated ``WorktreeMapping``.
    ///   - fromWorktree: Absolute path to the current worktree.
    ///   - toWorktree: Absolute path to the target worktree.
    ///   - readinessRule: The readiness rule to verify post-switch.
    ///   - runningContainerIds: Set of currently running container IDs
    ///     (used to resolve `.ifRunning` restart policy).
    public func planSwitch(
        mapping: WorktreeMapping,
        fromWorktree: String,
        toWorktree: String,
        readinessRule: ReadinessRule,
        runningContainerIds: Set<String>
    ) throws -> WorktreeSwitchPlan {
        let normalizedFrom = normalizePath(fromWorktree)
        let normalizedTo = normalizePath(toWorktree)
        let normalizedRepo = normalizePath(mapping.repoRoot)

        // Validate paths
        guard normalizedFrom.hasPrefix("/") else {
            throw WorktreeValidationError.fromWorktreeNotAbsolute(path: fromWorktree)
        }
        guard normalizedTo.hasPrefix("/") else {
            throw WorktreeValidationError.toWorktreeNotAbsolute(path: toWorktree)
        }
        guard normalizedFrom != normalizedTo else {
            throw WorktreeValidationError.switchToSameWorktree(worktree: fromWorktree)
        }
        guard normalizedFrom.hasPrefix(normalizedRepo) else {
            throw WorktreeValidationError.fromWorktreeOutsideRepo(
                path: fromWorktree, repoRoot: mapping.repoRoot
            )
        }
        guard normalizedTo.hasPrefix(normalizedRepo) else {
            throw WorktreeValidationError.toWorktreeOutsideRepo(
                path: toWorktree, repoRoot: mapping.repoRoot
            )
        }

        // Validate readiness rule
        switch readinessRule.mode {
        case .regexOnly, .healthThenRegex:
            if readinessRule.regexPattern == nil || readinessRule.regexPattern?.isEmpty == true {
                throw WorktreeValidationError.readinessRuleMissingRegex(mappingId: mapping.id)
            }
        case .healthOnly:
            break
        }

        if readinessRule.mustMatchCount < 1 {
            throw WorktreeValidationError.readinessRuleInvalidMatchCount(
                mappingId: mapping.id, count: readinessRule.mustMatchCount
            )
        }

        // Compute restart targets
        let restartTargets: [String]
        switch mapping.restartPolicy {
        case .never:
            restartTargets = []
        case .always:
            restartTargets = [mapping.targetId]
        case .ifRunning:
            restartTargets = runningContainerIds.contains(mapping.targetId)
                ? [mapping.targetId]
                : []
        }

        return WorktreeSwitchPlan(
            mappingId: mapping.id,
            fromWorktree: fromWorktree,
            toWorktree: toWorktree,
            restartTargets: restartTargets,
            verifyRule: readinessRule
        )
    }
}
