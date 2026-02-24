import Foundation
@testable import MiniDockerCore
import XCTest

final class ReadinessEvaluatorTests: XCTestCase {
    private let evaluator = ReadinessEvaluator()
    private let windowStart = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Helpers

    private func makeEntry(
        message: String,
        timestamp: Date? = nil
    ) -> LogEntry {
        LogEntry(
            engineContextId: "test",
            containerId: "c1",
            stream: .stdout,
            timestamp: timestamp ?? Date(timeIntervalSince1970: 1_000_100),
            message: message
        )
    }

    private func makeRule(
        mode: ReadinessMode,
        pattern: String? = nil,
        mustMatchCount: Int = 1,
        windowStartPolicy: ReadinessWindowStartPolicy = .containerStart
    ) -> ReadinessRule {
        ReadinessRule(
            mode: mode,
            regexPattern: pattern,
            mustMatchCount: mustMatchCount,
            windowStartPolicy: windowStartPolicy
        )
    }

    // MARK: - healthOnly

    func testHealthOnlyHealthy() throws {
        let rule = makeRule(mode: .healthOnly)
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: .healthy,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertTrue(result.healthSatisfied)
    }

    func testHealthOnlyUnhealthy() throws {
        let rule = makeRule(mode: .healthOnly)
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: .unhealthy,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertFalse(result.healthSatisfied)
    }

    func testHealthOnlyStarting() throws {
        let rule = makeRule(mode: .healthOnly)
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: .starting,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
    }

    func testHealthOnlyNilHealth() throws {
        let rule = makeRule(mode: .healthOnly)
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
    }

    // MARK: - regexOnly

    func testRegexOnlyMatchesPattern() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "Server started")
        let entries = [makeEntry(message: "Server started on port 8080")]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
        XCTAssertEqual(result.evaluatedEntries, 1)
    }

    func testRegexOnlyNoMatch() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "Server started")
        let entries = [makeEntry(message: "Loading configuration...")]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testRegexOnlyBelowMustMatchCount() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready", mustMatchCount: 2)
        let entries = [makeEntry(message: "ready")]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
    }

    func testRegexOnlyMeetsMustMatchCount() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready", mustMatchCount: 2)
        let entries = [
            makeEntry(message: "worker 1 ready"),
            makeEntry(message: "worker 2 ready"),
        ]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 2)
    }

    func testRegexOnlyStaleEntriesRejected() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready")
        let staleEntry = makeEntry(
            message: "ready",
            timestamp: Date(timeIntervalSince1970: 999_999)
        )
        let freshEntry = makeEntry(
            message: "still loading",
            timestamp: Date(timeIntervalSince1970: 1_000_100)
        )
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: [staleEntry, freshEntry], windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.rejectedStaleEntries, 1)
        XCTAssertEqual(result.evaluatedEntries, 1)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testRegexOnlyInvalidPattern() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "[invalid")
        do {
            _ = try evaluator.evaluate(
                rule: rule, healthStatus: nil,
                logEntries: [], windowStart: windowStart
            )
            XCTFail("Expected error for invalid regex")
        } catch let error as CoreError {
            if case let .contractViolation(expected, _) = error {
                XCTAssertEqual(expected, "valid regex pattern")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRegexOnlyNilPattern() throws {
        let rule = makeRule(mode: .regexOnly, pattern: nil)
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: [makeEntry(message: "anything")],
            windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testRegexOnlyEmptyEntries() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready")
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.evaluatedEntries, 0)
    }

    // MARK: - healthThenRegex

    func testHealthThenRegexShortCircuitsOnHealthy() throws {
        let rule = makeRule(mode: .healthThenRegex, pattern: "ready")
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: .healthy,
            logEntries: [], windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertTrue(result.healthSatisfied)
        XCTAssertEqual(result.evaluatedEntries, 0)
    }

    func testHealthThenRegexFallsBackToRegex() throws {
        let rule = makeRule(mode: .healthThenRegex, pattern: "ready")
        let entries = [makeEntry(message: "service ready")]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: .unhealthy,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertFalse(result.healthSatisfied)
        XCTAssertEqual(result.regexMatchCount, 1)
    }

    func testHealthThenRegexNilHealthFallsBack() throws {
        let rule = makeRule(mode: .healthThenRegex, pattern: "ready")
        let entries = [makeEntry(message: "ready")]
        let result = try evaluator.evaluate(
            rule: rule, healthStatus: nil,
            logEntries: entries, windowStart: windowStart
        )
        XCTAssertTrue(result.isReady)
        XCTAssertFalse(result.healthSatisfied)
    }
}
