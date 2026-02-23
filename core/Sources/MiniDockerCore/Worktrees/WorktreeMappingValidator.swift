import Foundation

/// Pure validation for ``WorktreeMapping`` instances.
///
/// No filesystem or Docker access — validates structural correctness only.
public struct WorktreeMappingValidator: Sendable {
    public init() {}

    /// Validate a single mapping. Throws on first error.
    public func validate(_ mapping: WorktreeMapping) throws {
        let errors = singleMappingErrors(mapping)
        if let first = errors.first {
            throw first
        }
    }

    /// Validate a collection including cross-mapping checks. Throws on first error.
    public func validateAll(_ mappings: [WorktreeMapping]) throws {
        let errors = allErrors(forAll: mappings)
        if let first = errors.first {
            throw first
        }
    }

    /// Return all errors for a single mapping (non-throwing, for UI feedback).
    public func allErrors(for mapping: WorktreeMapping) -> [WorktreeValidationError] {
        singleMappingErrors(mapping)
    }

    /// Return all errors for a collection including cross-collection checks.
    public func allErrors(forAll mappings: [WorktreeMapping]) -> [WorktreeValidationError] {
        var errors: [WorktreeValidationError] = []

        for mapping in mappings {
            errors.append(contentsOf: singleMappingErrors(mapping))
        }

        // Check for duplicate IDs
        var seen: Set<String> = []
        for mapping in mappings {
            if seen.contains(mapping.id) {
                errors.append(.duplicateMappingId(id: mapping.id))
            }
            seen.insert(mapping.id)
        }

        return errors
    }

    // MARK: - Private

    private func singleMappingErrors(_ mapping: WorktreeMapping) -> [WorktreeValidationError] {
        var errors: [WorktreeValidationError] = []

        if mapping.id.isEmpty {
            errors.append(.emptyMappingId)
        }

        let repoRoot = normalizePath(mapping.repoRoot)
        if !repoRoot.hasPrefix("/") {
            errors.append(.repoRootNotAbsolute(path: mapping.repoRoot))
        }

        let anchorPath = normalizePath(mapping.anchorPath)
        if !anchorPath.hasPrefix("/") {
            errors.append(.anchorPathNotAbsolute(path: mapping.anchorPath))
        } else if repoRoot.hasPrefix("/"), !anchorPath.hasPrefix(repoRoot) {
            errors.append(.anchorPathOutsideRepo(anchorPath: mapping.anchorPath, repoRoot: mapping.repoRoot))
        }

        if mapping.targetId.isEmpty {
            errors.append(.emptyTargetId)
        }

        return errors
    }
}

/// Strip trailing `/` from a path for consistent comparison.
func normalizePath(_ path: String) -> String {
    var p = path
    while p.count > 1, p.hasSuffix("/") {
        p = String(p.dropLast())
    }
    return p
}
