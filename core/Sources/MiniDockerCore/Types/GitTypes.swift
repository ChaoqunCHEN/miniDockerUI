import Foundation

/// A git worktree entry parsed from `git worktree list --porcelain`.
public struct GitWorktreeInfo: Sendable, Codable, Equatable {
    /// Absolute path to the worktree directory.
    public let path: String

    /// The HEAD commit SHA.
    public let head: String

    /// The branch name (e.g., "refs/heads/main"), or nil for detached HEAD.
    public let branch: String?

    /// Whether this is a bare worktree.
    public let isBare: Bool

    public init(path: String, head: String, branch: String?, isBare: Bool) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isBare = isBare
    }

    /// The short branch name (e.g., "main" from "refs/heads/main").
    public var shortBranch: String? {
        guard let branch else { return nil }
        if branch.hasPrefix("refs/heads/") {
            return String(branch.dropFirst("refs/heads/".count))
        }
        return branch
    }
}
