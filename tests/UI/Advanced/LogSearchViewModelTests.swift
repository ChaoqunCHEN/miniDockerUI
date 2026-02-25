import Foundation
@testable import MiniDockerCore
import XCTest

/// Tests the log search workflow as used by LogSearchViewModel:
/// real LogRingBuffer + LogSearchEngine with mock data.
/// Since ViewModels live in the executable target (not importable by tests),
/// we test the core search engine directly through the same scenarios.
@MainActor
final class LogSearchViewModelTests: XCTestCase {
    private let containerId = "test-container"

    private func makeBufferWithEntries(
        _ messages: [String],
        streams: [LogStream]? = nil
    ) -> LogRingBuffer {
        let buffer = TestHelpers.makeLogBuffer()
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        for (index, message) in messages.enumerated() {
            let stream = streams?[index] ?? .stdout
            let entry = TestHelpers.makeLogEntry(
                containerId: containerId,
                stream: stream,
                timestamp: baseDate.addingTimeInterval(Double(index)),
                message: message
            )
            buffer.append(entry)
        }
        return buffer
    }

    // MARK: - Substring Search

    func testSubstringSearchFindsMatches() {
        let buffer = makeBufferWithEntries([
            "Starting server on port 8080",
            "Database connected",
            "Server ready on port 8080",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "port",
            matchMode: .substring,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 2)
    }

    func testEmptyPatternReturnsNoResults() {
        let buffer = makeBufferWithEntries(["Hello world"])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "",
            matchMode: .substring,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Regex Search

    func testRegexSearchFindsMatches() {
        let buffer = makeBufferWithEntries([
            "Error: connection refused",
            "Warning: timeout",
            "Error: disk full",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "Error:.*",
            matchMode: .regex,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Exact Search

    func testExactSearchCaseSensitive() {
        let buffer = makeBufferWithEntries([
            "Hello",
            "Hello World",
            "hello",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "Hello",
            matchMode: .exact,
            caseSensitive: true,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.entry.message, "Hello")
    }

    // MARK: - Case Sensitivity

    func testCaseInsensitiveSearch() {
        let buffer = makeBufferWithEntries([
            "ERROR: something failed",
            "error: another failure",
            "Info: all good",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "error",
            matchMode: .substring,
            caseSensitive: false,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 2)
    }

    func testCaseSensitiveSearch() {
        let buffer = makeBufferWithEntries([
            "ERROR: something failed",
            "error: another failure",
            "Info: all good",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "ERROR",
            matchMode: .substring,
            caseSensitive: true,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Stream Filter

    func testStreamFilterStdout() {
        let buffer = makeBufferWithEntries(
            ["stdout msg", "stderr msg", "stdout msg2"],
            streams: [.stdout, .stderr, .stdout]
        )
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "msg",
            matchMode: .substring,
            streamFilter: [.stdout],
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertEqual(result.entry.stream, .stdout)
        }
    }

    // MARK: - No Results

    func testSearchNoMatchesReturnsEmpty() {
        let buffer = makeBufferWithEntries(["Hello world"])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "nonexistent",
            matchMode: .substring,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Match Ranges

    func testSubstringMatchRangesProvided() {
        let buffer = makeBufferWithEntries(["aaa bbb aaa"])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "aaa",
            matchMode: .substring,
            containerFilter: containerId
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.matchRanges.count, 2)
    }

    // MARK: - Max Results

    func testMaxResultsLimitsOutput() {
        let buffer = makeBufferWithEntries([
            "match 1", "match 2", "match 3", "match 4", "match 5",
        ])
        let engine = LogSearchEngine()

        let query = LogSearchQuery(
            pattern: "match",
            matchMode: .substring,
            containerFilter: containerId,
            maxResults: 3
        )
        let results = engine.search(in: buffer, query: query)

        XCTAssertEqual(results.count, 3)
    }
}
