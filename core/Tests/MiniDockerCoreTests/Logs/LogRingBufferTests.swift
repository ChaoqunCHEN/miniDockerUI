import Foundation
@testable import MiniDockerCore
import XCTest

final class LogRingBufferTests: XCTestCase {
    // MARK: - Helpers

    private func makePolicy(
        maxLines: Int = 100,
        maxBytes: Int = 1_000_000,
        strategy: LogDropStrategy = .dropOldest
    ) -> LogBufferPolicy {
        LogBufferPolicy(
            maxLinesPerContainer: maxLines,
            maxBytesPerContainer: maxBytes,
            dropStrategy: strategy,
            flushHz: 30
        )
    }

    private func makeEntry(
        containerId: String = "c1",
        message: String = "hello",
        timestamp: Date = Date()
    ) -> LogEntry {
        LogEntry(
            engineContextId: "ctx",
            containerId: containerId,
            stream: .stdout,
            timestamp: timestamp,
            message: message
        )
    }

    // MARK: - Basic Append & Retrieve

    func testAppendSingleEntry() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry())
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 1)
        let entries = buffer.entries(forContainer: "c1")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].message, "hello")
    }

    func testAppendMultipleContainers() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c2"))
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 1)
        XCTAssertEqual(buffer.lineCount(forContainer: "c2"), 1)
        XCTAssertEqual(buffer.totalLineCount, 2)
    }

    // MARK: - Drop Oldest

    func testLineCapDropOldest() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 3))
        for i in 0 ..< 4 {
            buffer.append(makeEntry(message: "msg-\(i)"))
        }
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 3)
        let entries = buffer.entries(forContainer: "c1")
        XCTAssertEqual(entries[0].message, "msg-1") // msg-0 evicted
        XCTAssertEqual(entries[2].message, "msg-3")
    }

    func testByteCapEvictionBeforeLineCap() {
        // Each entry with message "x" costs roughly: 1 + 2 + 3 + 64 = 70 bytes
        // Set byte cap to 150 (allows ~2 entries)
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 100, maxBytes: 150, strategy: .dropOldest))
        buffer.append(makeEntry(message: "x"))
        buffer.append(makeEntry(message: "x"))
        let evicted = buffer.append(makeEntry(message: "x"))
        XCTAssertGreaterThan(evicted, 0)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 2)
    }

    func testEvictionCountReturned() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 2))
        buffer.append(makeEntry(message: "a"))
        buffer.append(makeEntry(message: "b"))
        let evicted = buffer.append(makeEntry(message: "c"))
        XCTAssertEqual(evicted, 1)
    }

    func testDropOldestWraparound() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 3))
        // Fill and wrap around multiple times
        for i in 0 ..< 10 {
            buffer.append(makeEntry(message: "msg-\(i)"))
        }
        let entries = buffer.entries(forContainer: "c1")
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].message, "msg-7")
        XCTAssertEqual(entries[1].message, "msg-8")
        XCTAssertEqual(entries[2].message, "msg-9")
    }

    // MARK: - Drop Newest

    func testLineCapDropNewest() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 2, strategy: .dropNewest))
        buffer.append(makeEntry(message: "a"))
        buffer.append(makeEntry(message: "b"))
        let evicted = buffer.append(makeEntry(message: "c"))
        XCTAssertEqual(evicted, 0)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 2)
        let entries = buffer.entries(forContainer: "c1")
        XCTAssertEqual(entries[0].message, "a")
        XCTAssertEqual(entries[1].message, "b")
    }

    func testBlockProducerStrategy() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 2, strategy: .blockProducer))
        buffer.append(makeEntry(message: "a"))
        buffer.append(makeEntry(message: "b"))
        let evicted = buffer.append(makeEntry(message: "c"))
        XCTAssertEqual(evicted, 0)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 2)
    }

    // MARK: - Batch

    func testBatchAppend() {
        let buffer = LogRingBuffer(policy: makePolicy())
        let entries = (0 ..< 5).map { makeEntry(message: "msg-\($0)") }
        buffer.appendBatch(entries)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 5)
    }

    func testBatchAppendWithEviction() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 3))
        let entries = (0 ..< 5).map { makeEntry(message: "msg-\($0)") }
        let evicted = buffer.appendBatch(entries)
        XCTAssertEqual(evicted, 2)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 3)
    }

    // MARK: - Ordering & Filtering

    func testEntriesOrderOldestFirst() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 3))
        let base = Date()
        for i in 0 ..< 5 {
            buffer.append(makeEntry(message: "msg-\(i)", timestamp: base.addingTimeInterval(Double(i))))
        }
        let entries = buffer.entries(forContainer: "c1")
        XCTAssertTrue(entries[0].timestamp < entries[1].timestamp)
        XCTAssertTrue(entries[1].timestamp < entries[2].timestamp)
    }

    func testEntriesTimeRangeFilter() {
        let buffer = LogRingBuffer(policy: makePolicy())
        let base = Date()
        for i in 0 ..< 5 {
            buffer.append(makeEntry(message: "msg-\(i)", timestamp: base.addingTimeInterval(Double(i))))
        }
        let filtered = buffer.entries(
            forContainer: "c1",
            from: base.addingTimeInterval(1),
            to: base.addingTimeInterval(3)
        )
        XCTAssertEqual(filtered.count, 3) // indices 1, 2, 3
    }

    // MARK: - Counts

    func testLineCount() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c2"))
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 2)
        XCTAssertEqual(buffer.lineCount(forContainer: "c2"), 1)
    }

    func testByteCount() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(message: "hello"))
        XCTAssertGreaterThan(buffer.byteCount(forContainer: "c1"), 0)
    }

    func testTotalCounts() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c2"))
        XCTAssertEqual(buffer.totalLineCount, 2)
        XCTAssertGreaterThan(buffer.totalByteCount, 0)
    }

    // MARK: - Clear

    func testClearContainer() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c2"))
        buffer.clear(containerId: "c1")
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 0)
        XCTAssertEqual(buffer.lineCount(forContainer: "c2"), 1)
    }

    func testClearAll() {
        let buffer = LogRingBuffer(policy: makePolicy())
        buffer.append(makeEntry(containerId: "c1"))
        buffer.append(makeEntry(containerId: "c2"))
        buffer.clearAll()
        XCTAssertEqual(buffer.totalLineCount, 0)
        XCTAssertEqual(buffer.totalByteCount, 0)
    }

    // MARK: - Edge Cases

    func testEmptyBufferQueries() {
        let buffer = LogRingBuffer(policy: makePolicy())
        XCTAssertTrue(buffer.entries(forContainer: "c1").isEmpty)
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 0)
        XCTAssertEqual(buffer.byteCount(forContainer: "c1"), 0)
        XCTAssertEqual(buffer.totalLineCount, 0)
    }

    func testHighVolumeAppend() {
        let buffer = LogRingBuffer(policy: makePolicy(maxLines: 50))
        for i in 0 ..< 1000 {
            buffer.append(makeEntry(message: "msg-\(i)"))
        }
        XCTAssertEqual(buffer.lineCount(forContainer: "c1"), 50)
    }
}
