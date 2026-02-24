import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Readiness Integration Tests

/// Integration-level tests that exercise ReadinessEvaluator across
/// all modes and cross-integrate with LogRingBuffer and LogSearchEngine.
final class ReadinessIntegrationTests: XCTestCase {
    private let evaluator = ReadinessEvaluator()
    private let windowStart = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Helpers

    private func makeEntry(
        containerId: String = "c1",
        message: String,
        timestamp: Date? = nil,
        stream: LogStream = .stdout
    ) -> LogEntry {
        LogEntry(
            engineContextId: "integ-ctx",
            containerId: containerId,
            stream: stream,
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

    // MARK: - S5: Health-only with all status variants

    func testHealthOnlyWithAllStatusVariants() throws {
        let rule = makeRule(mode: .healthOnly)

        let cases: [(ContainerHealthStatus?, Bool)] = [
            (.healthy, true),
            (.unhealthy, false),
            (.starting, false),
            (.none, false),
            (.unknown, false),
            (nil, false),
        ]

        for (status, expectedReady) in cases {
            let result = try evaluator.evaluate(
                rule: rule,
                healthStatus: status,
                logEntries: [],
                windowStart: windowStart
            )
            XCTAssertEqual(
                result.isReady, expectedReady,
                "Expected isReady=\(expectedReady) for health status \(String(describing: status))"
            )
        }
    }

    // MARK: - S5: Regex with realistic log entries

    func testRegexWithRealisticLogEntries() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "listening on port \\d+")
        let entries = [
            makeEntry(message: "Starting application..."),
            makeEntry(message: "Loading configuration from /etc/app.conf"),
            makeEntry(message: "Database connection established"),
            makeEntry(message: "Server listening on port 8080"),
            makeEntry(message: "Worker pool initialized with 4 threads"),
        ]

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 1)
        XCTAssertEqual(result.evaluatedEntries, 5)
        XCTAssertEqual(result.rejectedStaleEntries, 0)
    }

    // MARK: - S5: Stale-line rejection with mixed timestamps

    func testStaleLineRejectionWithMixedTimestamps() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready")

        // 25 stale entries (before windowStart), 25 fresh entries
        var entries: [LogEntry] = []
        for i in 0 ..< 25 {
            entries.append(makeEntry(
                message: "stale ready \(i)",
                timestamp: Date(timeIntervalSince1970: Double(999_975 + i))
            ))
        }
        for i in 0 ..< 25 {
            entries.append(makeEntry(
                message: i % 2 == 0 ? "fresh ready \(i)" : "fresh loading \(i)",
                timestamp: Date(timeIntervalSince1970: Double(1_000_000 + i))
            ))
        }

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertEqual(result.rejectedStaleEntries, 25)
        XCTAssertEqual(result.evaluatedEntries, 25)
        // Fresh entries: indices 0,2,4,...,24 match "ready" = 13 matches
        XCTAssertEqual(result.regexMatchCount, 13)
        XCTAssertTrue(result.isReady)
    }

    // MARK: - S5: Health-then-regex fallback chain

    func testHealthThenRegexFallbackChain() throws {
        let rule = makeRule(mode: .healthThenRegex, pattern: "ready")
        let entries = [makeEntry(message: "service ready")]

        // Healthy → short-circuit, skip regex
        let healthyResult = try evaluator.evaluate(
            rule: rule,
            healthStatus: .healthy,
            logEntries: entries,
            windowStart: windowStart
        )
        XCTAssertTrue(healthyResult.isReady)
        XCTAssertTrue(healthyResult.healthSatisfied)
        XCTAssertEqual(healthyResult.evaluatedEntries, 0, "Should not evaluate logs when healthy")

        // Starting → fall back to regex
        let startingResult = try evaluator.evaluate(
            rule: rule,
            healthStatus: .starting,
            logEntries: entries,
            windowStart: windowStart
        )
        XCTAssertTrue(startingResult.isReady)
        XCTAssertFalse(startingResult.healthSatisfied)
        XCTAssertEqual(startingResult.regexMatchCount, 1)

        // Nil health → fall back to regex
        let nilResult = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )
        XCTAssertTrue(nilResult.isReady)
        XCTAssertFalse(nilResult.healthSatisfied)
    }

    // MARK: - S5: mustMatchCount accumulation

    func testMustMatchCountAccumulation() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "worker \\d+ ready", mustMatchCount: 3)
        let entries = [
            makeEntry(message: "worker 1 ready"),
            makeEntry(message: "worker 2 initializing"),
            makeEntry(message: "worker 2 ready"),
            makeEntry(message: "worker 3 ready"),
        ]

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 3)
        XCTAssertEqual(result.evaluatedEntries, 4)
    }

    // MARK: - S5: Window start boundary is inclusive

    func testWindowStartBoundaryIsInclusive() throws {
        let rule = makeRule(mode: .regexOnly, pattern: "ready")

        // Entry at exactly windowStart should be INCLUDED
        // (ReadinessEvaluator uses `entry.timestamp < windowStart` to reject)
        let atBoundary = makeEntry(
            message: "ready",
            timestamp: windowStart
        )
        let beforeBoundary = makeEntry(
            message: "ready",
            timestamp: Date(timeIntervalSince1970: windowStart.timeIntervalSince1970 - 0.001)
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: [beforeBoundary, atBoundary],
            windowStart: windowStart
        )

        // beforeBoundary should be rejected, atBoundary should be evaluated
        XCTAssertEqual(result.rejectedStaleEntries, 1)
        XCTAssertEqual(result.evaluatedEntries, 1)
        XCTAssertEqual(result.regexMatchCount, 1)
        XCTAssertTrue(result.isReady)
    }

    // MARK: - S5: LogRingBuffer feed into ReadinessEvaluator

    func testLogRingBufferFeedIntoReadinessEvaluator() throws {
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 200,
            maxBytesPerContainer: 100_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        // Write 100 entries, every 10th matches "checkpoint"
        for i in 0 ..< 100 {
            let msg = i % 10 == 0 ? "checkpoint reached at step \(i)" : "processing step \(i)"
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "buf-test",
                stream: .stdout,
                timestamp: Date(timeIntervalSince1970: Double(1_000_000 + i)),
                message: msg
            )
            buffer.append(entry)
        }

        XCTAssertEqual(buffer.lineCount(forContainer: "buf-test"), 100)

        // Read entries back and feed to evaluator
        let entries = buffer.entries(forContainer: "buf-test")
        let rule = makeRule(mode: .regexOnly, pattern: "checkpoint", mustMatchCount: 5)

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 10) // indices 0,10,20,...,90
        XCTAssertEqual(result.evaluatedEntries, 100)
    }

    // MARK: - S5: LogSearch then ReadinessEvaluator

    func testLogSearchThenReadinessCheck() throws {
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 500,
            maxBytesPerContainer: 500_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)
        let searchEngine = LogSearchEngine()

        // Populate buffer with mixed log messages
        let messages = [
            "Starting database migration...",
            "Migration step 1 of 5 complete",
            "Migration step 2 of 5 complete",
            "ERROR: connection timeout during step 3",
            "Migration step 3 of 5 complete (retry succeeded)",
            "Migration step 4 of 5 complete",
            "Migration step 5 of 5 complete",
            "All migrations complete, server ready",
        ]

        for (i, msg) in messages.enumerated() {
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "search-test",
                stream: msg.contains("ERROR") ? .stderr : .stdout,
                timestamp: Date(timeIntervalSince1970: Double(1_000_100 + i)),
                message: msg
            )
            buffer.append(entry)
        }

        // Search for "complete" to find migration progress
        let query = LogSearchQuery(
            pattern: "complete",
            matchMode: .substring,
            containerFilter: "search-test"
        )
        let searchResults = searchEngine.search(in: buffer, query: query)
        XCTAssertEqual(searchResults.count, 6) // 5 steps + "All migrations complete"

        // Feed the matched entries into the readiness evaluator
        let matchedEntries = searchResults.map(\.entry)
        let rule = makeRule(mode: .regexOnly, pattern: "complete", mustMatchCount: 5)

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: matchedEntries,
            windowStart: windowStart
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.regexMatchCount, 6)
        XCTAssertEqual(result.evaluatedEntries, 6)
    }
}
