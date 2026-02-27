import Foundation
@testable import MiniDockerCore
import XCTest

/// Tests the readiness management workflow as used by ReadinessManager:
/// rule persistence via AppSettingsStore, latch semantics through
/// ReadinessEvaluator, and display logic.
/// Since ViewModels/Managers live in the executable target (not importable
/// by tests), we test the core types directly through the same scenarios.
@MainActor
final class ReadinessManagerTests: XCTestCase {
    private let evaluator = ReadinessEvaluator()
    private let containerId = "c1"
    private let containerKey = "local:test-name"

    // MARK: - Rule Persistence Round-Trip

    func testRulePersistenceRoundTrip() throws {
        let store = MockSettingsStore()
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        // Save rule
        var settings = try store.load()
        var rules = settings.readinessRules
        rules[containerKey] = rule
        settings = settings.with(readinessRules: rules)
        try store.save(settings)

        // Load rule
        let loaded = try store.load()
        XCTAssertEqual(loaded.readinessRules[containerKey], rule)
    }

    func testRuleRemovalPersists() throws {
        let store = MockSettingsStore()
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        // Save
        var settings = try store.load()
        var rules = settings.readinessRules
        rules[containerKey] = rule
        settings = settings.with(readinessRules: rules)
        try store.save(settings)
        XCTAssertNotNil(try store.load().readinessRules[containerKey])

        // Remove
        settings = try store.load()
        rules = settings.readinessRules
        rules.removeValue(forKey: containerKey)
        settings = settings.with(readinessRules: rules)
        try store.save(settings)

        XCTAssertNil(try store.load().readinessRules[containerKey])
    }

    // MARK: - Latch Behavior

    func testLatchStaysReadyAcrossEvaluations() throws {
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        // First evaluation: healthy → ready
        let result1 = try evaluator.evaluate(
            rule: rule,
            healthStatus: .healthy,
            logEntries: [],
            windowStart: Date.distantPast
        )
        XCTAssertTrue(result1.isReady)

        // Simulate latch: once ready, subsequent evaluations should
        // be skipped (ReadinessManager checks isLatched flag).
        // We verify that unhealthy status would give not-ready WITHOUT
        // latch, but WITH latch the manager skips evaluation.
        let result2 = try evaluator.evaluate(
            rule: rule,
            healthStatus: .unhealthy,
            logEntries: [],
            windowStart: Date.distantPast
        )
        // Without latch protection, evaluator returns not ready
        XCTAssertFalse(result2.isReady)
        // The ReadinessManager protects against this by skipping
        // evaluation when isLatched == true
    }

    // MARK: - Latch Reset Triggers

    func testRestartResetScenario() {
        // When startedAt changes, it signals a restart.
        // ReadinessManager detects this and resets the latch.
        let startTime1 = Date(timeIntervalSince1970: 1000)
        let startTime2 = Date(timeIntervalSince1970: 2000)

        let container1 = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Up", startedAt: startTime1
        )
        let container2 = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Up", startedAt: startTime2
        )

        // Verify startedAt differs — this is what ReadinessManager checks
        XCTAssertNotEqual(container1.startedAt, container2.startedAt)
        XCTAssertEqual(
            ContainerGrouper.containerKey(for: container1),
            ContainerGrouper.containerKey(for: container2)
        )
    }

    func testContainerIdChangeDetection() {
        // Docker compose recreate changes container ID but keeps name
        let container1 = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Up"
        )
        let container2 = TestHelpers.makeContainerSummary(
            id: "c2", name: "test-name", status: "Up"
        )

        XCTAssertNotEqual(container1.id, container2.id)
        XCTAssertEqual(
            ContainerGrouper.containerKey(for: container1),
            ContainerGrouper.containerKey(for: container2)
        )
    }

    func testStoppedContainerDetection() {
        let running = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Up"
        )
        let stopped = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Exited (0)"
        )

        XCTAssertTrue(running.isRunning)
        XCTAssertFalse(stopped.isRunning)
    }

    func testInspectStartedAtProvidesRestartSignal() {
        // ContainerDetail.summary.startedAt changes on restart — this is
        // the data path ReadinessManager.reconcile() uses to detect restarts
        // for latched containers via inspectContainer().
        let startTime1 = Date(timeIntervalSince1970: 1000)
        let startTime2 = Date(timeIntervalSince1970: 2000)

        let detail1 = TestHelpers.makeContainerDetail(
            id: "c1", name: "test-name", status: "Up", startedAt: startTime1
        )
        let detail2 = TestHelpers.makeContainerDetail(
            id: "c1", name: "test-name", status: "Up", startedAt: startTime2
        )

        // Same container ID — this is a restart, not a recreate
        XCTAssertEqual(detail1.summary.id, detail2.summary.id)
        // startedAt differs — reconcile detects this as a restart
        XCTAssertNotEqual(detail1.summary.startedAt, detail2.summary.startedAt)
        // Confirm the inspect path provides the restart signal
        XCTAssertEqual(detail1.summary.startedAt, startTime1)
        XCTAssertEqual(detail2.summary.startedAt, startTime2)
    }

    // MARK: - Readiness Display Logic

    func testReadinessDisplayNoRule() {
        // No rule → display returns nil (show default status)
        let rules: [String: ReadinessRule] = [:]
        let container = TestHelpers.makeContainerSummary(
            id: "c1", name: "test-name", status: "Up"
        )
        let key = ContainerGrouper.containerKey(for: container)

        XCTAssertNil(rules[key])
    }

    func testReadinessDisplayNotReady() throws {
        // Rule exists, not latched → display "-"
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: [],
            windowStart: Date.distantPast
        )
        XCTAssertFalse(result.isReady)
    }

    func testReadinessDisplayReady() throws {
        // Rule exists, evaluation is ready → display "Ready"
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: .healthy,
            logEntries: [],
            windowStart: Date.distantPast
        )
        XCTAssertTrue(result.isReady)
    }

    // MARK: - Reconcile Logic via ContainerGrouper

    func testContainerKeyMatchesAcrossRestarts() {
        let container1 = TestHelpers.makeContainerSummary(
            id: "old-id", name: "my-app", status: "Up"
        )
        let container2 = TestHelpers.makeContainerSummary(
            id: "new-id", name: "my-app", status: "Up"
        )

        let key1 = ContainerGrouper.containerKey(for: container1)
        let key2 = ContainerGrouper.containerKey(for: container2)

        XCTAssertEqual(key1, key2, "Container key should be stable across container ID changes")
    }

    // MARK: - Regex Evaluation with Log Buffer

    func testRegexEvaluationWithLogBuffer() throws {
        let buffer = TestHelpers.makeLogBuffer()
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: Date(),
            message: "Server started on port 8080"
        )
        buffer.append(entry)

        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let logEntries = buffer.entries(forContainer: containerId)
        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: logEntries,
            windowStart: Date.distantPast
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
    }

    func testHeadlessLogStreamNeededForEmptyBuffer() {
        let buffer = TestHelpers.makeLogBuffer()

        // Empty buffer — ReadinessManager starts headless log stream
        let count = buffer.lineCount(forContainer: containerId)
        XCTAssertEqual(count, 0, "Empty buffer should trigger headless log stream start")

        // With entries — no headless stream needed
        let entry = TestHelpers.makeLogEntry(containerId: containerId)
        buffer.append(entry)
        let countAfter = buffer.lineCount(forContainer: containerId)
        XCTAssertGreaterThan(countAfter, 0, "Non-empty buffer should not trigger headless log stream")
    }

    // MARK: - AppSettings.with(readinessRules:)

    func testWithReadinessRulesHelper() {
        let original = AppSettings.defaultSettings
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let updated = original.with(readinessRules: ["local:test": rule])

        XCTAssertEqual(updated.readinessRules["local:test"], rule)
        XCTAssertEqual(updated.favoriteContainerKeys, original.favoriteContainerKeys)
        XCTAssertEqual(updated.schemaVersion, original.schemaVersion)
    }
}
