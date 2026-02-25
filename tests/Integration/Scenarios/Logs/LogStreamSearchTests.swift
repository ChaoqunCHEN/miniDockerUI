import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Log Stream Search Tests

/// Tests for LogSearchEngine filtering capabilities: stream filtering,
/// time-windowed search, max results, regex under burst, and case sensitivity.
final class LogStreamSearchTests: XCTestCase {
    private let searchEngine = LogSearchEngine()

    private func makeBuffer(lineCap: Int = 10000) -> LogRingBuffer {
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 10_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        return LogRingBuffer(policy: policy)
    }

    // MARK: - Stream Filter Tests

    func testStreamFilterSeparatesStdoutAndStderr() {
        let buffer = makeBuffer()

        // Populate with mixed stdout/stderr entries
        for i in 0 ..< 100 {
            let stream: LogStream = i % 3 == 0 ? .stderr : .stdout
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "stream-filter",
                stream: stream,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i)),
                message: "message \(i) on \(stream.rawValue)"
            )
            buffer.append(entry)
        }

        // Search only stdout
        let stdoutQuery = LogSearchQuery(
            pattern: "message",
            matchMode: .substring,
            streamFilter: [.stdout],
            containerFilter: "stream-filter"
        )
        let stdoutResults = searchEngine.search(in: buffer, query: stdoutQuery)

        // Search only stderr
        let stderrQuery = LogSearchQuery(
            pattern: "message",
            matchMode: .substring,
            streamFilter: [.stderr],
            containerFilter: "stream-filter"
        )
        let stderrResults = searchEngine.search(in: buffer, query: stderrQuery)

        // Every 3rd entry (i%3==0) goes to stderr: 0,3,6,...,99 = 34 entries
        // The rest go to stdout: 100 - 34 = 66 entries
        XCTAssertEqual(stderrResults.count, 34, "Should have 34 stderr entries (i%3==0)")
        XCTAssertEqual(stdoutResults.count, 66, "Should have 66 stdout entries")

        // Verify all stdout results are stdout
        for result in stdoutResults {
            XCTAssertEqual(result.entry.stream, .stdout)
        }

        // Verify all stderr results are stderr
        for result in stderrResults {
            XCTAssertEqual(result.entry.stream, .stderr)
        }
    }

    func testTimeWindowedSearchFiltersCorrectly() {
        let buffer = makeBuffer()

        let baseTime = Date(timeIntervalSince1970: 1_000_000)

        // Create entries spanning a time range: 0..99 seconds from base
        for i in 0 ..< 100 {
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "time-window",
                stream: .stdout,
                timestamp: baseTime.addingTimeInterval(Double(i)),
                message: "event-\(i)"
            )
            buffer.append(entry)
        }

        // Search only entries from second 25 to second 75
        let fromDate = baseTime.addingTimeInterval(25)
        let toDate = baseTime.addingTimeInterval(75)

        let query = LogSearchQuery(
            pattern: "event",
            matchMode: .substring,
            containerFilter: "time-window",
            fromDate: fromDate,
            toDate: toDate
        )
        let results = searchEngine.search(in: buffer, query: query)

        // Should include entries 25..75 inclusive = 51 entries
        XCTAssertEqual(results.count, 51, "Should include entries from second 25 to 75 inclusive")

        // Verify boundary entries are present
        XCTAssertTrue(results.first?.entry.message.contains("event-25") ?? false)
        XCTAssertTrue(results.last?.entry.message.contains("event-75") ?? false)
    }

    func testMaxResultsLimitsSearchOutput() {
        let buffer = makeBuffer()

        for i in 0 ..< 1000 {
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "max-results",
                stream: .stdout,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i)),
                message: "matching line \(i)"
            )
            buffer.append(entry)
        }

        let query = LogSearchQuery(
            pattern: "matching",
            matchMode: .substring,
            containerFilter: "max-results",
            maxResults: 50
        )
        let results = searchEngine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 50, "Should limit results to maxResults")

        // Verify count API still reports the full count
        let fullCount = searchEngine.count(in: buffer, query: LogSearchQuery(
            pattern: "matching",
            matchMode: .substring,
            containerFilter: "max-results"
        ))
        XCTAssertEqual(fullCount, 1000, "Count should report total matches regardless of maxResults")
    }

    func testRegexSearchUnderBurstLoad() {
        let buffer = makeBuffer(lineCap: 50000)

        // Burst load: 20K entries with specific patterns
        for i in 0 ..< 20000 {
            let message: String
            switch i % 50 {
            case 0:
                message = "ERROR [2026-01-15] connection timeout after 30s"
            case 10:
                message = "WARN [2026-01-15] slow query took 5.2s"
            case 25:
                message = "INFO [2026-01-15] health check passed (200 OK)"
            default:
                message = "DEBUG [2026-01-15] processing request \(i)"
            }

            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "regex-burst",
                stream: .stdout,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 0.001),
                message: message
            )
            buffer.append(entry)
        }

        // Regex: find entries with timing info (e.g., "30s" or "5.2s")
        let query = LogSearchQuery(
            pattern: "\\d+\\.?\\d*s$",
            matchMode: .regex,
            caseSensitive: true,
            containerFilter: "regex-burst"
        )
        let results = searchEngine.search(in: buffer, query: query)

        // Entries at i%50==0 match "30s" (400 entries)
        // Entries at i%50==10 match "5.2s" (400 entries)
        XCTAssertEqual(results.count, 800, "Should find 800 entries with timing pattern")
    }

    func testCaseInsensitiveSearchAfterBurst() {
        let buffer = makeBuffer()

        let messages = [
            "Server READY to accept connections",
            "Database ready for queries",
            "Cache Ready",
            "Worker not initialized",
            "Load balancer healthy",
        ]

        for i in 0 ..< 500 {
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "case-search",
                stream: .stdout,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i)),
                message: messages[i % messages.count]
            )
            buffer.append(entry)
        }

        // Case-insensitive search for "ready"
        let caseInsensitiveQuery = LogSearchQuery(
            pattern: "ready",
            matchMode: .substring,
            caseSensitive: false,
            containerFilter: "case-search"
        )
        let insensitiveResults = searchEngine.search(in: buffer, query: caseInsensitiveQuery)

        // Case-sensitive search for "ready"
        let caseSensitiveQuery = LogSearchQuery(
            pattern: "ready",
            matchMode: .substring,
            caseSensitive: true,
            containerFilter: "case-search"
        )
        let sensitiveResults = searchEngine.search(in: buffer, query: caseSensitiveQuery)

        // Case-insensitive should match: "READY", "ready", "Ready" = 3 of every 5 messages
        // 500 / 5 * 3 = 300
        XCTAssertEqual(insensitiveResults.count, 300, "Case-insensitive should match all variants of 'ready'")

        // Case-sensitive should only match "ready" (lowercase) = 1 of every 5
        // 500 / 5 = 100
        XCTAssertEqual(sensitiveResults.count, 100, "Case-sensitive should only match lowercase 'ready'")
    }
}
