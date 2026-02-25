import Foundation
@testable import MiniDockerCore
import XCTest

/// Tests the worktree switch workflow as used by WorktreeSwitchViewModel:
/// real WorktreeSwitchPlanner + WorktreeMappingValidator with mock data.
/// Since ViewModels live in the executable target (not importable by tests),
/// we test the core planner directly through the same scenarios.
@MainActor
final class WorktreeSwitchViewModelTests: XCTestCase {
    private let planner = WorktreeSwitchPlanner()
    private let validator = WorktreeMappingValidator()

    private func makeMapping(
        id: String = "mapping-1",
        repoRoot: String = "/repo",
        targetId: String = "container-1",
        restartPolicy: WorktreeRestartPolicy = .always
    ) -> WorktreeMapping {
        WorktreeMapping(
            id: id,
            repoRoot: repoRoot,
            anchorPath: "\(repoRoot)/anchor",
            targetType: .container,
            targetId: targetId,
            restartPolicy: restartPolicy
        )
    }

    private func defaultRule() -> ReadinessRule {
        ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
    }

    // MARK: - Valid Plans

    func testPlanSwitchValidWithAlwaysRestart() throws {
        let mapping = makeMapping(restartPolicy: .always)

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/repo/feature-a",
            toWorktree: "/repo/feature-b",
            readinessRule: defaultRule(),
            runningContainerIds: ["container-1"]
        )

        XCTAssertEqual(plan.mappingId, "mapping-1")
        XCTAssertEqual(plan.fromWorktree, "/repo/feature-a")
        XCTAssertEqual(plan.toWorktree, "/repo/feature-b")
        XCTAssertEqual(plan.restartTargets, ["container-1"])
    }

    func testPlanSwitchNeverRestartPolicy() throws {
        let mapping = makeMapping(restartPolicy: .never)

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/repo/feature-a",
            toWorktree: "/repo/feature-b",
            readinessRule: defaultRule(),
            runningContainerIds: ["container-1"]
        )

        XCTAssertTrue(plan.restartTargets.isEmpty)
    }

    func testPlanSwitchIfRunningPolicyWhenRunning() throws {
        let mapping = makeMapping(restartPolicy: .ifRunning)

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/repo/feature-a",
            toWorktree: "/repo/feature-b",
            readinessRule: defaultRule(),
            runningContainerIds: ["container-1"]
        )

        XCTAssertEqual(plan.restartTargets, ["container-1"])
    }

    func testPlanSwitchIfRunningPolicyWhenNotRunning() throws {
        let mapping = makeMapping(restartPolicy: .ifRunning)

        let plan = try planner.planSwitch(
            mapping: mapping,
            fromWorktree: "/repo/feature-a",
            toWorktree: "/repo/feature-b",
            readinessRule: defaultRule(),
            runningContainerIds: []
        )

        XCTAssertTrue(plan.restartTargets.isEmpty)
    }

    // MARK: - Validation Errors

    func testSameWorktreeThrows() {
        let mapping = makeMapping()

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/repo/feature-a",
                toWorktree: "/repo/feature-a",
                readinessRule: defaultRule(),
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.switchToSameWorktree = error else {
                XCTFail("Expected switchToSameWorktree, got \(error)")
                return
            }
        }
    }

    func testFromWorktreeNotAbsoluteThrows() {
        let mapping = makeMapping()

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "relative/path",
                toWorktree: "/repo/feature-b",
                readinessRule: defaultRule(),
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.fromWorktreeNotAbsolute = error else {
                XCTFail("Expected fromWorktreeNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testToWorktreeNotAbsoluteThrows() {
        let mapping = makeMapping()

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/repo/feature-a",
                toWorktree: "relative/path",
                readinessRule: defaultRule(),
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.toWorktreeNotAbsolute = error else {
                XCTFail("Expected toWorktreeNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testFromWorktreeOutsideRepoThrows() {
        let mapping = makeMapping(repoRoot: "/repo")

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/other-repo/feature-a",
                toWorktree: "/repo/feature-b",
                readinessRule: defaultRule(),
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.fromWorktreeOutsideRepo = error else {
                XCTFail("Expected fromWorktreeOutsideRepo, got \(error)")
                return
            }
        }
    }

    func testToWorktreeOutsideRepoThrows() {
        let mapping = makeMapping(repoRoot: "/repo")

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/repo/feature-a",
                toWorktree: "/other-repo/feature-b",
                readinessRule: defaultRule(),
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.toWorktreeOutsideRepo = error else {
                XCTFail("Expected toWorktreeOutsideRepo, got \(error)")
                return
            }
        }
    }

    // MARK: - Readiness Rule Validation

    func testMissingRegexForRegexModeThrows() {
        let mapping = makeMapping()
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        XCTAssertThrowsError(
            try planner.planSwitch(
                mapping: mapping,
                fromWorktree: "/repo/feature-a",
                toWorktree: "/repo/feature-b",
                readinessRule: rule,
                runningContainerIds: []
            )
        ) { error in
            guard case WorktreeValidationError.readinessRuleMissingRegex = error else {
                XCTFail("Expected readinessRuleMissingRegex, got \(error)")
                return
            }
        }
    }

    // MARK: - Mapping Validation

    func testMappingValidatorAcceptsValidMapping() throws {
        let mapping = makeMapping()
        XCTAssertNoThrow(try validator.validate(mapping))
    }

    func testMappingValidatorRejectsEmptyId() {
        let mapping = WorktreeMapping(
            id: "",
            repoRoot: "/repo",
            anchorPath: "/repo/anchor",
            targetType: .container,
            targetId: "container-1",
            restartPolicy: .always
        )

        XCTAssertThrowsError(try validator.validate(mapping)) { error in
            guard case WorktreeValidationError.emptyMappingId = error else {
                XCTFail("Expected emptyMappingId, got \(error)")
                return
            }
        }
    }
}
