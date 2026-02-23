import Foundation
@testable import MiniDockerCore
import XCTest

final class WorktreeSwitchPlannerTests: XCTestCase {
    private let planner = WorktreeSwitchPlanner()

    private func validMapping(
        restartPolicy: WorktreeRestartPolicy = .always,
        targetId: String = "container-1"
    ) -> WorktreeMapping {
        WorktreeMapping(
            id: "m1",
            repoRoot: "/repo",
            anchorPath: "/repo/anchor",
            targetType: .container,
            targetId: targetId,
            restartPolicy: restartPolicy
        )
    }

    private func healthOnlyRule() -> ReadinessRule {
        ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
    }

    private func regexRule() -> ReadinessRule {
        ReadinessRule(
            mode: .regexOnly,
            regexPattern: "ready",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
    }

    // MARK: - Restart Policies

    func testPlanAlwaysRestart() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(restartPolicy: .always),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )
        XCTAssertEqual(plan.restartTargets, ["container-1"])
    }

    func testPlanNeverRestart() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(restartPolicy: .never),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: ["container-1"]
        )
        XCTAssertTrue(plan.restartTargets.isEmpty)
    }

    func testPlanIfRunningWhenRunning() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(restartPolicy: .ifRunning),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: ["container-1"]
        )
        XCTAssertEqual(plan.restartTargets, ["container-1"])
    }

    func testPlanIfRunningWhenStopped() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(restartPolicy: .ifRunning),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )
        XCTAssertTrue(plan.restartTargets.isEmpty)
    }

    // MARK: - Path Validation Errors

    func testSameWorktreeFails() {
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-a",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.switchToSameWorktree = error else {
                XCTFail("Expected switchToSameWorktree, got \(error)")
                return
            }
        }
    }

    func testFromWorktreeNotAbsoluteFails() {
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "relative/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.fromWorktreeNotAbsolute = error else {
                XCTFail("Expected fromWorktreeNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testToWorktreeNotAbsoluteFails() {
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "relative/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.toWorktreeNotAbsolute = error else {
                XCTFail("Expected toWorktreeNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testFromWorktreeOutsideRepoFails() {
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/other/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.fromWorktreeOutsideRepo = error else {
                XCTFail("Expected fromWorktreeOutsideRepo, got \(error)")
                return
            }
        }
    }

    func testToWorktreeOutsideRepoFails() {
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/other/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.toWorktreeOutsideRepo = error else {
                XCTFail("Expected toWorktreeOutsideRepo, got \(error)")
                return
            }
        }
    }

    // MARK: - Readiness Rule Validation

    func testReadinessRuleMissingRegexFails() {
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: rule,
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.readinessRuleMissingRegex = error else {
                XCTFail("Expected readinessRuleMissingRegex, got \(error)")
                return
            }
        }
    }

    func testReadinessRuleInvalidCountFails() {
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 0,
            windowStartPolicy: .containerStart
        )
        XCTAssertThrowsError(try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: rule,
            runningContainerIds: []
        )) { error in
            guard case WorktreeValidationError.readinessRuleInvalidMatchCount = error else {
                XCTFail("Expected readinessRuleInvalidMatchCount, got \(error)")
                return
            }
        }
    }

    func testHealthOnlyModeNoRegexRequired() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )
        XCTAssertNotNil(plan)
    }

    // MARK: - Plan Content

    func testVerifyRulePassedThrough() throws {
        let rule = regexRule()
        let plan = try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: rule,
            runningContainerIds: []
        )
        XCTAssertEqual(plan.verifyRule, rule)
    }

    func testPlanContainsCorrectMappingId() throws {
        let plan = try planner.planSwitch(
            mapping: validMapping(),
            fromWorktree: "/repo/wt-a",
            toWorktree: "/repo/wt-b",
            readinessRule: healthOnlyRule(),
            runningContainerIds: []
        )
        XCTAssertEqual(plan.mappingId, "m1")
        XCTAssertEqual(plan.fromWorktree, "/repo/wt-a")
        XCTAssertEqual(plan.toWorktree, "/repo/wt-b")
    }
}
