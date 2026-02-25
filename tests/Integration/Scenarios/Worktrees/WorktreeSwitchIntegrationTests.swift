import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Worktree Switch Integration Tests

/// Integration tests for WorktreeSwitchPlanner, validating full switch flows
/// including policy-based restart decisions, error conditions, and real Docker
/// restart verification.
final class WorktreeSwitchIntegrationTests: XCTestCase {
    private let planner = WorktreeSwitchPlanner()

    // MARK: - Helpers

    private func makeMapping(
        id: String = "map-1",
        repoRoot: String = "/Users/dev/myrepo",
        targetId: String = "my-container",
        restartPolicy: WorktreeRestartPolicy = .ifRunning
    ) -> WorktreeMapping {
        WorktreeMapping(
            id: id,
            repoRoot: repoRoot,
            anchorPath: "\(repoRoot)/docker-compose.yml",
            targetType: .container,
            targetId: targetId,
            restartPolicy: restartPolicy
        )
    }

    private func makeReadinessRule(
        mode: ReadinessMode = .regexOnly,
        pattern: String? = "ready",
        mustMatchCount: Int = 1
    ) -> ReadinessRule {
        ReadinessRule(
            mode: mode,
            regexPattern: pattern,
            mustMatchCount: mustMatchCount,
            windowStartPolicy: .containerStart
        )
    }

    // MARK: - Mock Tests

    func testFullSwitchFlowWithMockAdapter() async throws {
        let mock = ScenarioMockCommandRunner()

        // Configure mock to return a running container for list
        let listJSON = """
        {"ID":"abc123","Names":"my-container","Image":"nginx:1.25","Status":"Up 5 minutes","Labels":"","CreatedAt":"2026-01-10 08:00:00 +0000 UTC"}
        """
        mock.runHandler = { request in
            if request.arguments.contains("ps") {
                return CommandResult(exitCode: 0, stdout: listJSON.data(using: .utf8)!)
            }
            return CommandResult(exitCode: 0)
        }
        mock.runCheckedHandler = { _ in
            CommandResult(exitCode: 0)
        }

        let adapter = CLIEngineAdapter(
            dockerPath: "/usr/local/bin/docker",
            engineContextId: "integ-ctx",
            runner: mock
        )

        // Step 1: Validate — get running containers
        let containers = try await adapter.listContainers()
        let runningIds = Set(containers.filter(\.isRunning).map(\.id))

        // Step 2: Plan the switch
        let mapping = makeMapping(targetId: "abc123", restartPolicy: .ifRunning)
        let rule = makeReadinessRule()

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/Users/dev/myrepo/feature-a",
            toWorktree: "/Users/dev/myrepo/feature-b",
            readinessRule: rule,
            runningContainerIds: runningIds
        )

        XCTAssertEqual(plan.mappingId, "map-1")
        XCTAssertEqual(plan.fromWorktree, "/Users/dev/myrepo/feature-a")
        XCTAssertEqual(plan.toWorktree, "/Users/dev/myrepo/feature-b")
        XCTAssertEqual(plan.restartTargets, ["abc123"], "Running container should be in restart targets")

        // Step 3: Execute restart
        for target in plan.restartTargets {
            try await adapter.restartContainer(id: target, timeoutSeconds: nil)
        }

        // Verify restart was called
        let restartRequests = mock.capturedRunCheckedRequests.filter {
            $0.arguments.contains("restart")
        }
        XCTAssertEqual(restartRequests.count, 1)
        XCTAssertTrue(restartRequests[0].arguments.contains("abc123"))
    }

    func testSwitchWithIfRunningPolicyContainerRunning() throws {
        let mapping = makeMapping(restartPolicy: .ifRunning)
        let rule = makeReadinessRule()

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/Users/dev/myrepo/branch-a",
            toWorktree: "/Users/dev/myrepo/branch-b",
            readinessRule: rule,
            runningContainerIds: ["my-container"]
        )

        XCTAssertEqual(
            plan.restartTargets,
            ["my-container"],
            "ifRunning should include target when it is running"
        )
    }

    func testSwitchWithIfRunningPolicyContainerNotRunning() throws {
        let mapping = makeMapping(restartPolicy: .ifRunning)
        let rule = makeReadinessRule()

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/Users/dev/myrepo/branch-a",
            toWorktree: "/Users/dev/myrepo/branch-b",
            readinessRule: rule,
            runningContainerIds: ["other-container"]
        )

        XCTAssertTrue(
            plan.restartTargets.isEmpty,
            "ifRunning should not include target when it is not running"
        )
    }

    func testSwitchWithNeverPolicySkipsRestart() throws {
        let mapping = makeMapping(restartPolicy: .never)
        let rule = makeReadinessRule()

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/Users/dev/myrepo/branch-a",
            toWorktree: "/Users/dev/myrepo/branch-b",
            readinessRule: rule,
            runningContainerIds: ["my-container"]
        )

        XCTAssertTrue(
            plan.restartTargets.isEmpty,
            "never policy should always produce empty restart targets"
        )
    }

    func testSwitchWithAlwaysPolicyAlwaysRestarts() throws {
        let mapping = makeMapping(restartPolicy: .always)
        let rule = makeReadinessRule()

        // Even with no running containers
        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/Users/dev/myrepo/branch-a",
            toWorktree: "/Users/dev/myrepo/branch-b",
            readinessRule: rule,
            runningContainerIds: []
        )

        XCTAssertEqual(
            plan.restartTargets,
            ["my-container"],
            "always policy should include target regardless of running state"
        )
    }

    func testSwitchToSameWorktreeRejected() throws {
        let mapping = makeMapping()
        let rule = makeReadinessRule()

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/Users/dev/myrepo/branch-a",
                toWorktree: "/Users/dev/myrepo/branch-a",
                readinessRule: rule,
                runningContainerIds: []
            )
        ) { error in
            guard let validationError = error as? WorktreeValidationError else {
                XCTFail("Expected WorktreeValidationError, got \(error)")
                return
            }
            if case .switchToSameWorktree = validationError {
                // Expected
            } else {
                XCTFail("Expected switchToSameWorktree, got \(validationError)")
            }
        }
    }

    func testSwitchToWorktreeOutsideRepoRejected() throws {
        let mapping = makeMapping(repoRoot: "/Users/dev/myrepo")
        let rule = makeReadinessRule()

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/Users/dev/myrepo/branch-a",
                toWorktree: "/Users/dev/otherrepo/branch-b",
                readinessRule: rule,
                runningContainerIds: []
            )
        ) { error in
            guard let validationError = error as? WorktreeValidationError else {
                XCTFail("Expected WorktreeValidationError, got \(error)")
                return
            }
            if case .toWorktreeOutsideRepo = validationError {
                // Expected
            } else {
                XCTFail("Expected toWorktreeOutsideRepo, got \(validationError)")
            }
        }
    }

    // MARK: - Real Docker Test

    func testRealDockerSwitchRestartAndVerifyState() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let adapter = CLIEngineAdapter()
        let runID = "switch-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        let handles: [FixtureHandle]
        do {
            handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [sleepDescriptor(key: "switch-target")],
                desiredStates: [.running]
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        let containerId = handles[0].containerId

        // Verify container is running
        let beforeContainers = try await adapter.listContainers()
        let beforeTarget = beforeContainers.first { $0.id == containerId }
        XCTAssertNotNil(beforeTarget)
        XCTAssertTrue(beforeTarget?.isRunning ?? false, "Container should be running before switch")

        // Plan a switch with always-restart policy
        let mapping = WorktreeMapping(
            id: "real-switch-map",
            repoRoot: "/tmp/testrepo",
            anchorPath: "/tmp/testrepo/docker-compose.yml",
            targetType: .container,
            targetId: containerId,
            restartPolicy: .always
        )
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/tmp/testrepo/branch-a",
            toWorktree: "/tmp/testrepo/branch-b",
            readinessRule: rule,
            runningContainerIds: [containerId]
        )

        XCTAssertEqual(plan.restartTargets.count, 1)

        // Execute the restart
        for target in plan.restartTargets {
            try await adapter.restartContainer(id: target, timeoutSeconds: 10)
        }

        // Allow time for restart
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Verify container is still running after restart
        let afterContainers = try await adapter.listContainers()
        let afterTarget = afterContainers.first { $0.id == containerId }
        XCTAssertNotNil(afterTarget)
        XCTAssertTrue(afterTarget?.isRunning ?? false, "Container should be running after restart")
    }
}
