import Foundation
@testable import MiniDockerCore
import XCTest

final class LogSearchEngineTests: XCTestCase {
    private let engine = LogSearchEngine()

    private func makeBuffer(entries: [LogEntry]) -> LogRingBuffer {
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 10000,
            maxBytesPerContainer: 10_000_000,
            dropStrategy: .dropOldest,
            flushHz: 30
        )
        let buffer = LogRingBuffer(policy: policy)
        buffer.appendBatch(entries)
        return buffer
    }

    private func makeEntry(
        containerId: String = "c1",
        stream: LogStream = .stdout,
        message: String = "hello",
        timestamp: Date = Date()
    ) -> LogEntry {
        LogEntry(
            engineContextId: "ctx",
            containerId: containerId,
            stream: stream,
            timestamp: timestamp,
            message: message
        )
    }

    // MARK: - Substring Search

    func testSubstringSearchCaseInsensitive() {
        let buffer = makeBuffer(entries: [
            makeEntry(message: "Hello World"),
            makeEntry(message: "hello earth"),
            makeEntry(message: "no match"),
        ])
        let query = LogSearchQuery(pattern: "hello", containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 2)
    }

    func testSubstringSearchCaseSensitive() {
        let buffer = makeBuffer(entries: [
            makeEntry(message: "Hello World"),
            makeEntry(message: "hello earth"),
        ])
        let query = LogSearchQuery(pattern: "Hello", caseSensitive: true, containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.message, "Hello World")
    }

    // MARK: - Regex Search

    func testRegexSearch() {
        let buffer = makeBuffer(entries: [
            makeEntry(message: "ERROR: something failed"),
            makeEntry(message: "WARNING: low disk"),
            makeEntry(message: "INFO: all good"),
        ])
        let query = LogSearchQuery(pattern: "ERROR|WARNING", matchMode: .regex, containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 2)
    }

    func testInvalidRegexReturnsEmpty() {
        let buffer = makeBuffer(entries: [makeEntry(message: "test")])
        let query = LogSearchQuery(pattern: "[invalid", matchMode: .regex, containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Exact Search

    func testExactSearch() {
        let buffer = makeBuffer(entries: [
            makeEntry(message: "exact match"),
            makeEntry(message: "exact match plus more"),
        ])
        let query = LogSearchQuery(pattern: "exact match", matchMode: .exact, containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.message, "exact match")
    }

    // MARK: - Filters

    func testStreamFilter() {
        let buffer = makeBuffer(entries: [
            makeEntry(stream: .stdout, message: "log-out"),
            makeEntry(stream: .stderr, message: "log-err"),
        ])
        let query = LogSearchQuery(
            pattern: "log-",
            streamFilter: [.stderr],
            containerFilter: "c1"
        )
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.stream, .stderr)
    }

    func testContainerFilter() {
        let buffer = makeBuffer(entries: [
            makeEntry(containerId: "c1", message: "match"),
            makeEntry(containerId: "c2", message: "match"),
        ])
        let query = LogSearchQuery(pattern: "match", containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.containerId, "c1")
    }

    func testDateRangeFilter() {
        let base = Date()
        let buffer = makeBuffer(entries: [
            makeEntry(message: "log-early", timestamp: base),
            makeEntry(message: "log-mid", timestamp: base.addingTimeInterval(10)),
            makeEntry(message: "log-late", timestamp: base.addingTimeInterval(20)),
        ])
        let query = LogSearchQuery(
            pattern: "log-",
            containerFilter: "c1",
            fromDate: base.addingTimeInterval(5),
            toDate: base.addingTimeInterval(15)
        )
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.message, "log-mid")
    }

    // MARK: - Max Results & Count

    func testMaxResults() {
        let buffer = makeBuffer(entries: (0 ..< 10).map {
            makeEntry(message: "match-\($0)")
        })
        let query = LogSearchQuery(pattern: "match", containerFilter: "c1", maxResults: 3)
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 3)
    }

    func testCountWithoutMaterializing() {
        let buffer = makeBuffer(entries: (0 ..< 5).map {
            makeEntry(message: "match-\($0)")
        })
        let query = LogSearchQuery(pattern: "match", containerFilter: "c1")
        let count = engine.count(in: buffer, query: query)
        XCTAssertEqual(count, 5)
    }

    func testNoMatchReturnsEmpty() {
        let buffer = makeBuffer(entries: [makeEntry(message: "hello")])
        let query = LogSearchQuery(pattern: "xyz", containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchMatchRanges() {
        let buffer = makeBuffer(entries: [makeEntry(message: "hello world hello")])
        let query = LogSearchQuery(pattern: "hello", containerFilter: "c1")
        let results = engine.search(in: buffer, query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].matchRanges.count, 2)
    }
}
