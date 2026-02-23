import Foundation

/// Validation errors for worktree mappings and switch plans.
public enum WorktreeValidationError: Error, Sendable, Equatable {
    // MARK: - Single-mapping validation

    case emptyMappingId
    case repoRootNotAbsolute(path: String)
    case anchorPathNotAbsolute(path: String)
    case anchorPathOutsideRepo(anchorPath: String, repoRoot: String)
    case emptyTargetId

    // MARK: - Collection validation

    case duplicateMappingId(id: String)

    // MARK: - Readiness rule validation

    case readinessRuleMissingRegex(mappingId: String)
    case readinessRuleInvalidMatchCount(mappingId: String, count: Int)

    // MARK: - Switch plan validation

    case switchToSameWorktree(worktree: String)
    case fromWorktreeNotAbsolute(path: String)
    case toWorktreeNotAbsolute(path: String)
    case fromWorktreeOutsideRepo(path: String, repoRoot: String)
    case toWorktreeOutsideRepo(path: String, repoRoot: String)
}
