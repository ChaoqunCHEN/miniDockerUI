import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Mock Command Runner

private final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    var runHandler: ((CommandRequest) async throws -> CommandResult)?
    var runCheckedHandler: ((CommandRequest) async throws -> CommandResult)?
    var streamHandler: ((CommandRequest) -> AsyncThrowingStream<Data, Error>)?

    private(set) var capturedRunRequests: [CommandRequest] = []

    func run(_ request: CommandRequest) async throws -> CommandResult {
        capturedRunRequests.append(request)
        guard let handler = runHandler else {
            return CommandResult(exitCode: 0)
        }
        return try await handler(request)
    }

    func runChecked(_ request: CommandRequest) async throws -> CommandResult {
        guard let handler = runCheckedHandler else {
            let result = try await run(request)
            guard result.isSuccess else {
                throw CoreError.processNonZeroExit(
                    executablePath: request.executablePath,
                    exitCode: result.exitCode,
                    stderr: result.stderrString
                )
            }
            return result
        }
        return try await handler(request)
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        guard let handler = streamHandler else {
            return AsyncThrowingStream { $0.finish() }
        }
        return handler(request)
    }
}

// MARK: - Parser Tests

final class GitWorktreeParserTests: XCTestCase {
    // MARK: - testParseSingleWorktree

    func testParseSingleWorktree() {
        let output = """
        worktree /Users/dev/myrepo
        HEAD abc123def456
        branch refs/heads/main

        """
        let result = parseWorktreeListPorcelain(output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/dev/myrepo")
        XCTAssertEqual(result[0].head, "abc123def456")
        XCTAssertEqual(result[0].branch, "refs/heads/main")
        XCTAssertFalse(result[0].isBare)
    }

    // MARK: - testParseMultipleWorktrees

    func testParseMultipleWorktrees() {
        let output = """
        worktree /Users/dev/myrepo
        HEAD abc123def456
        branch refs/heads/main

        worktree /Users/dev/myrepo-feature
        HEAD def456abc123
        branch refs/heads/feature-branch

        """
        let result = parseWorktreeListPorcelain(output)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, "/Users/dev/myrepo")
        XCTAssertEqual(result[0].branch, "refs/heads/main")
        XCTAssertEqual(result[1].path, "/Users/dev/myrepo-feature")
        XCTAssertEqual(result[1].branch, "refs/heads/feature-branch")
    }

    // MARK: - testParseDetachedHead

    func testParseDetachedHead() {
        let output = """
        worktree /Users/dev/myrepo
        HEAD abc123def456
        detached

        """
        let result = parseWorktreeListPorcelain(output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/dev/myrepo")
        XCTAssertEqual(result[0].head, "abc123def456")
        XCTAssertNil(result[0].branch)
        XCTAssertFalse(result[0].isBare)
    }

    // MARK: - testParseBareRepo

    func testParseBareRepo() {
        let output = """
        worktree /Users/dev/myrepo.git
        HEAD abc123def456
        bare

        """
        let result = parseWorktreeListPorcelain(output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/dev/myrepo.git")
        XCTAssertEqual(result[0].head, "abc123def456")
        XCTAssertNil(result[0].branch)
        XCTAssertTrue(result[0].isBare)
    }

    // MARK: - testParseEmptyOutput

    func testParseEmptyOutput() {
        let result = parseWorktreeListPorcelain("")
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - testParseMalformedOutput

    func testParseMalformedOutput() {
        // An entry with only a worktree line (no HEAD) should be skipped.
        let output = """
        worktree /Users/dev/myrepo

        HEAD abc123def456

        worktree /Users/dev/good
        HEAD def456abc123
        branch refs/heads/main

        """
        let result = parseWorktreeListPorcelain(output)
        // Only the last complete entry should be parsed.
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/dev/good")
        XCTAssertEqual(result[0].head, "def456abc123")
    }
}

// MARK: - Adapter Tests

final class GitCLIAdapterTests: XCTestCase {
    private var mock: MockCommandRunner!
    private var adapter: GitCLIAdapter!

    override func setUp() {
        mock = MockCommandRunner()
        adapter = GitCLIAdapter(
            gitPath: "/usr/bin/git",
            runner: mock
        )
    }

    // MARK: - repoRoot

    func testRepoRootBuildsCorrectArguments() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 0,
                stdout: "/Users/dev/myrepo\n".data(using: .utf8)!
            )
        }
        _ = try await adapter.repoRoot(for: "/Users/dev/myrepo/subdir")
        let req = mock.capturedRunRequests.first
        XCTAssertEqual(req?.executablePath, "/usr/bin/git")
        XCTAssertEqual(req?.arguments, ["-C", "/Users/dev/myrepo/subdir", "rev-parse", "--show-toplevel"])
    }

    func testRepoRootParsesOutput() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 0,
                stdout: "  /Users/dev/myrepo  \n".data(using: .utf8)!
            )
        }
        let root = try await adapter.repoRoot(for: "/Users/dev/myrepo")
        XCTAssertEqual(root, "/Users/dev/myrepo")
    }

    func testRepoRootThrowsForNonGitDir() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 128,
                stderr: "fatal: not a git repository".data(using: .utf8)!
            )
        }
        do {
            _ = try await adapter.repoRoot(for: "/tmp/not-a-repo")
            XCTFail("Expected gitNotARepository error")
        } catch let error as CoreError {
            if case let .gitNotARepository(directory) = error {
                XCTAssertEqual(directory, "/tmp/not-a-repo")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - listWorktrees

    func testListWorktreesBuildsCorrectArguments() async throws {
        mock.runHandler = { _ in
            CommandResult(exitCode: 0)
        }
        _ = try await adapter.listWorktrees(repoRoot: "/Users/dev/myrepo")
        let req = mock.capturedRunRequests.first
        XCTAssertEqual(req?.executablePath, "/usr/bin/git")
        XCTAssertEqual(req?.arguments, ["-C", "/Users/dev/myrepo", "worktree", "list", "--porcelain"])
    }

    func testListWorktreesParsesOutput() async throws {
        let porcelainOutput = """
        worktree /Users/dev/myrepo
        HEAD abc123def456
        branch refs/heads/main

        worktree /Users/dev/myrepo-feature
        HEAD def456abc123
        branch refs/heads/feature-branch

        """
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 0,
                stdout: porcelainOutput.data(using: .utf8)!
            )
        }
        let worktrees = try await adapter.listWorktrees(repoRoot: "/Users/dev/myrepo")
        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].path, "/Users/dev/myrepo")
        XCTAssertEqual(worktrees[0].head, "abc123def456")
        XCTAssertEqual(worktrees[0].branch, "refs/heads/main")
        XCTAssertFalse(worktrees[0].isBare)
        XCTAssertEqual(worktrees[1].path, "/Users/dev/myrepo-feature")
        XCTAssertEqual(worktrees[1].branch, "refs/heads/feature-branch")
    }

    func testListWorktreesThrowsOnNonZeroExit() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 1,
                stderr: "not a git repository".data(using: .utf8)!
            )
        }
        do {
            _ = try await adapter.listWorktrees(repoRoot: "/tmp/bad")
            XCTFail("Expected gitWorktreeListFailed error")
        } catch let error as CoreError {
            if case let .gitWorktreeListFailed(repoRoot, reason) = error {
                XCTAssertEqual(repoRoot, "/tmp/bad")
                XCTAssertEqual(reason, "not a git repository")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}
