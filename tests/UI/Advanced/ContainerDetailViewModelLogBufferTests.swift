import Foundation
@testable import MiniDockerCore
import XCTest

/// Tests the LogRingBuffer integration as used by ContainerDetailViewModel:
/// append, read, clear, and capacity behavior.
/// Since ViewModels live in the executable target (not importable by tests),
/// we test the core LogRingBuffer directly through the same scenarios.
@MainActor
final class ContainerDetailViewModelLogBufferTests: XCTestCase {
    private let containerId = "test-container"

    // MARK: - Buffer Integration

    func testBufferStartsEmpty() {
        let buffer = TestHelpers.makeLogBuffer()
        XCTAssertEqual(buffer.lineCount(forContainer: containerId), 0)
        XCTAssertEqual(buffer.byteCount(forContainer: containerId), 0)
        XCTAssertTrue(buffer.entries(forContainer: containerId).isEmpty)
    }

    func testAppendAndRetrieveEntries() {
        let buffer = TestHelpers.makeLogBuffer()
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            message: "test log line"
        )
        buffer.append(entry)

        let entries = buffer.entries(forContainer: containerId)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "test log line")
        XCTAssertEqual(buffer.lineCount(forContainer: containerId), 1)
    }

    func testClearRemovesAllEntries() {
        let buffer = TestHelpers.makeLogBuffer()
        let entry = TestHelpers.makeLogEntry(
            containerId: containerId,
            message: "will be cleared"
        )
        buffer.append(entry)
        XCTAssertEqual(buffer.lineCount(forContainer: containerId), 1)

        buffer.clear(containerId: containerId)

        XCTAssertEqual(buffer.lineCount(forContainer: containerId), 0)
        XCTAssertTrue(buffer.entries(forContainer: containerId).isEmpty)
    }

    func testMultipleEntriesPreserveOrder() {
        let buffer = TestHelpers.makeLogBuffer()
        let baseDate = Date(timeIntervalSince1970: 1_000_000)

        for i in 0 ..< 100 {
            let entry = TestHelpers.makeLogEntry(
                containerId: containerId,
                timestamp: baseDate.addingTimeInterval(Double(i)),
                message: "Log line \(i)"
            )
            buffer.append(entry)
        }

        let entries = buffer.entries(forContainer: containerId)
        XCTAssertEqual(entries.count, 100)
        XCTAssertEqual(entries.first?.message, "Log line 0")
        XCTAssertEqual(entries.last?.message, "Log line 99")
    }

    func testRingBufferEvictsOldestWhenFull() {
        let buffer = LogRingBuffer(policy: LogBufferPolicy(
            maxLinesPerContainer: 10,
            maxBytesPerContainer: 1_000_000,
            dropStrategy: .dropOldest,
            flushHz: 30
        ))

        for i in 0 ..< 20 {
            let entry = TestHelpers.makeLogEntry(
                containerId: containerId,
                timestamp: Date().addingTimeInterval(Double(i)),
                message: "Line \(i)"
            )
            buffer.append(entry)
        }

        let entries = buffer.entries(forContainer: containerId)
        XCTAssertEqual(entries.count, 10)
        // Should contain lines 10-19 (oldest 0-9 evicted)
        XCTAssertEqual(entries.first?.message, "Line 10")
        XCTAssertEqual(entries.last?.message, "Line 19")
    }
}
