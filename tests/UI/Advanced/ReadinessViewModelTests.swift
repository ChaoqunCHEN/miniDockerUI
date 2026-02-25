import Foundation
@testable import MiniDockerCore
import XCTest

/// Tests the readiness evaluation workflow as used by ReadinessViewModel:
/// real ReadinessEvaluator + LogRingBuffer with mock data.
/// Since ViewModels live in the executable target (not importable by tests),
/// we test the core evaluator directly through the same scenarios.
@MainActor
final class ReadinessViewModelTests: XCTestCase {
    private let containerId = "test-container"
    private let evaluator = ReadinessEvaluator()

    // MARK: - Health Only Mode

    func testHealthOnlyReadyWhenHealthy() throws {
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
        XCTAssertTrue(result.healthSatisfied)
    }

    func testHealthOnlyNotReadyWhenUnhealthy() throws {
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: .unhealthy,
            logEntries: [],
            windowStart: Date.distantPast
        )

        XCTAssertFalse(result.isReady)
        XCTAssertFalse(result.healthSatisfied)
    }

    func testHealthOnlyNotReadyWhenNil() throws {
        let rule = ReadinessRule(
            mode: .healthOnly,
            regexPattern: nil,
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

    // MARK: - Regex Only Mode

    func testRegexOnlyReadyWhenPatternMatches() throws {
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: Date(),
            message: "Server started on port 8080"
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: [entry],
            windowStart: Date.distantPast
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
        XCTAssertEqual(result.evaluatedEntries, 1)
    }

    func testRegexOnlyNotReadyWhenNoMatch() throws {
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: Date(),
            message: "Database connecting..."
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: [entry],
            windowStart: Date.distantPast
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testRegexOnlyRejectsStaleEntries() throws {
        let windowStart = Date(timeIntervalSince1970: 1_000_000)
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "Server started",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let staleEntry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: windowStart.addingTimeInterval(-10),
            message: "Server started (stale)"
        )
        let freshEntry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: windowStart.addingTimeInterval(10),
            message: "Server started (fresh)"
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: [staleEntry, freshEntry],
            windowStart: windowStart
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
        XCTAssertEqual(result.rejectedStaleEntries, 1)
        XCTAssertEqual(result.evaluatedEntries, 1)
    }

    func testRegexOnlyMustMatchCountRequiresMultiple() throws {
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "ready",
            mustMatchCount: 3,
            windowStartPolicy: .containerStart
        )

        let entries = (0 ..< 2).map { i in
            TestHelpers.makeLogEntry(
                containerId: containerId,
                timestamp: Date().addingTimeInterval(Double(i)),
                message: "ready \(i)"
            )
        }

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: Date.distantPast
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 2)
    }

    // MARK: - Health Then Regex Mode

    func testHealthThenRegexShortCircuitsOnHealthy() throws {
        let rule = ReadinessRule(
            mode: .healthThenRegex,
            regexPattern: "will-not-match",
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
        XCTAssertTrue(result.healthSatisfied)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testHealthThenRegexFallsBackToRegex() throws {
        let rule = ReadinessRule(
            mode: .healthThenRegex,
            regexPattern: "Ready to accept",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            timestamp: Date(),
            message: "Ready to accept connections"
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: .unhealthy,
            logEntries: [entry],
            windowStart: Date.distantPast
        )

        XCTAssertTrue(result.isReady)
        XCTAssertFalse(result.healthSatisfied)
        XCTAssertEqual(result.regexMatchCount, 1)
    }

    // MARK: - Invalid Regex

    func testInvalidRegexThrowsError() {
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "[invalid",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        XCTAssertThrowsError(
            try evaluator.evaluate(
                rule: rule,
                healthStatus: nil,
                logEntries: [TestHelpers.makeLogEntry(containerId: containerId)],
                windowStart: Date.distantPast
            )
        ) { error in
            guard case CoreError.contractViolation = error else {
                XCTFail("Expected CoreError.contractViolation, got \(error)")
                return
            }
        }
    }
}
