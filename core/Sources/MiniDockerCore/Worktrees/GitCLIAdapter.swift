import Foundation

/// Protocol for git operations needed by the worktree feature.
public protocol GitAdapter: Sendable {
    /// Discover the repository root for a given directory.
    func repoRoot(for directory: String) async throws -> String

    /// List all worktrees for a given repository root.
    func listWorktrees(repoRoot: String) async throws -> [GitWorktreeInfo]
}

/// Implements ``GitAdapter`` by shelling out to the `git` CLI.
///
/// Follows the same pattern as ``CLIEngineAdapter``: uses a
/// ``CommandRunning`` runner for testability and checks
/// ``CommandResult/isSuccess`` to decide between parsing and throwing.
public struct GitCLIAdapter: GitAdapter, Sendable {
    private let runner: any CommandRunning
    private let gitPath: String

    /// Default timeout for one-shot git commands (seconds).
    private let defaultTimeout: Double = 10

    public init(
        gitPath: String = "/usr/bin/git",
        runner: any CommandRunning = CLICommandRunner()
    ) {
        self.gitPath = gitPath
        self.runner = runner
    }

    // MARK: - GitAdapter

    public func repoRoot(for directory: String) async throws -> String {
        let request = CommandRequest(
            executablePath: gitPath,
            arguments: ["-C", directory, "rev-parse", "--show-toplevel"],
            timeoutSeconds: defaultTimeout
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw CoreError.gitNotARepository(directory: directory)
        }
        return result.stdoutString
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func listWorktrees(repoRoot: String) async throws -> [GitWorktreeInfo] {
        let request = CommandRequest(
            executablePath: gitPath,
            arguments: ["-C", repoRoot, "worktree", "list", "--porcelain"],
            timeoutSeconds: defaultTimeout
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw CoreError.gitWorktreeListFailed(
                repoRoot: repoRoot,
                reason: result.stderrString
            )
        }
        return parseWorktreeListPorcelain(result.stdoutString)
    }
}

// MARK: - Porcelain Parser

/// Parse the porcelain output of `git worktree list --porcelain` into
/// an array of ``GitWorktreeInfo`` values.
///
/// Each worktree entry in the porcelain format is separated by a blank
/// line. Within an entry:
/// - `worktree <path>` — always present
/// - `HEAD <sha>` — always present
/// - `branch <ref>` — present unless detached HEAD
/// - `detached` — present when HEAD is detached
/// - `bare` — present for bare repositories
///
/// Entries that lack the required `worktree` or `HEAD` lines are
/// silently skipped to handle malformed output gracefully.
func parseWorktreeListPorcelain(_ output: String) -> [GitWorktreeInfo] {
    guard !output.isEmpty else { return [] }

    // Split the output into blocks separated by blank lines.
    let blocks = output.components(separatedBy: "\n\n")

    var worktrees: [GitWorktreeInfo] = []

    for block in blocks {
        let lines = block.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { continue }

        var path: String?
        var head: String?
        var branch: String?
        var isBare = false

        for line in lines {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
            } else if line == "bare" {
                isBare = true
            }
            // "detached" lines are noted by the absence of a branch
        }

        // Both path and HEAD are required; skip malformed entries.
        guard let worktreePath = path, let headSHA = head else {
            continue
        }

        worktrees.append(GitWorktreeInfo(
            path: worktreePath,
            head: headSHA,
            branch: branch,
            isBare: isBare
        ))
    }

    return worktrees
}
