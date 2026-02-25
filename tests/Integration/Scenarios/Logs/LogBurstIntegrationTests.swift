import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Log Burst Integration Tests

/// Tests for high-volume log ingestion into LogRingBuffer with various
/// policies, plus cross-integration with LogSearchEngine after burst loads.
final class LogBurstIntegrationTests: XCTestCase {
    // MARK: - Mock Tests

    func testLogBurstRespectLineCapWithDropOldest() {
        let lineCap = 10000
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 100_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        let entries = LogEntryFactory.makeBatch(
            containerId: "burst-container",
            count: 50000,
            bytesPerLine: 40
        )
        buffer.appendBatch(entries)

        XCTAssertEqual(
            buffer.lineCount(forContainer: "burst-container"),
            lineCap,
            "Buffer should cap at maxLinesPerContainer"
        )

        // Verify we kept the newest entries (dropOldest evicts old)
        let stored = buffer.entries(forContainer: "burst-container")
        XCTAssertEqual(stored.count, lineCap)

        let firstStored = stored[0]
        XCTAssertTrue(
            firstStored.message.contains("line-040000"),
            "Oldest stored entry should be around index 40000, got: \(firstStored.message)"
        )

        let lastStored = stored[lineCap - 1]
        XCTAssertTrue(
            lastStored.message.contains("line-049999"),
            "Newest stored entry should be the last generated"
        )
    }

    func testLogBurstRespectByteCapWithDropOldest() {
        let byteCap = 50000
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 100_000,
            maxBytesPerContainer: byteCap,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        let entries = LogEntryFactory.makeBatch(
            containerId: "byte-cap",
            count: 5000,
            bytesPerLine: 80
        )
        buffer.appendBatch(entries)

        let storedBytes = buffer.byteCount(forContainer: "byte-cap")
        XCTAssertLessThanOrEqual(
            storedBytes,
            byteCap,
            "Byte count should not exceed maxBytesPerContainer"
        )

        let storedLines = buffer.lineCount(forContainer: "byte-cap")
        XCTAssertLessThan(
            storedLines,
            5000,
            "Some entries should have been evicted due to byte cap"
        )
    }

    func testLogBurstDropNewestRejectsOverflow() {
        let lineCap = 1000
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 10_000_000,
            dropStrategy: .dropNewest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        let entries = LogEntryFactory.makeBatch(
            containerId: "drop-newest",
            count: 5000,
            bytesPerLine: 40
        )
        buffer.appendBatch(entries)

        XCTAssertEqual(
            buffer.lineCount(forContainer: "drop-newest"),
            lineCap,
            "Buffer should contain exactly lineCap entries"
        )

        // With dropNewest, the first entries should be preserved
        let stored = buffer.entries(forContainer: "drop-newest")
        let firstStored = stored[0]
        XCTAssertTrue(
            firstStored.message.contains("line-000000"),
            "First entry should be the very first generated (dropNewest keeps old)"
        )

        let lastStored = stored[lineCap - 1]
        XCTAssertTrue(
            lastStored.message.contains("line-000999"),
            "Last stored entry should be at index 999"
        )
    }

    func testSearchAfterBurstLoadReturnsCorrectResults() {
        let lineCap = 50000
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 100_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)
        let searchEngine = LogSearchEngine()

        // Generate entries where every 100th has a searchable marker
        for i in 0 ..< 50000 {
            let message: String
            if i % 100 == 0 {
                message = "CHECKPOINT-MARKER at step \(i)"
            } else {
                message = "regular log line \(i) with padding data"
            }
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "search-burst",
                stream: .stdout,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 0.001),
                message: message
            )
            buffer.append(entry)
        }

        let query = LogSearchQuery(
            pattern: "CHECKPOINT-MARKER",
            matchMode: .substring,
            containerFilter: "search-burst"
        )
        let results = searchEngine.search(in: buffer, query: query)

        // 50_000 / 100 = 500 markers
        XCTAssertEqual(results.count, 500, "Should find exactly 500 checkpoint markers")

        // Verify count API matches
        let count = searchEngine.count(in: buffer, query: query)
        XCTAssertEqual(count, 500)
    }

    func testMultiContainerBurstIndependentCaps() {
        let lineCap = 5000
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 100_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        // Populate two containers with different volumes
        let entriesA = LogEntryFactory.makeBatch(
            containerId: "container-a",
            count: 10000,
            bytesPerLine: 40
        )
        let entriesB = LogEntryFactory.makeBatch(
            containerId: "container-b",
            count: 3000,
            bytesPerLine: 40
        )

        buffer.appendBatch(entriesA)
        buffer.appendBatch(entriesB)

        // Container A should be capped
        XCTAssertEqual(
            buffer.lineCount(forContainer: "container-a"),
            lineCap,
            "Container A should be capped at lineCap"
        )

        // Container B should have all entries (under cap)
        XCTAssertEqual(
            buffer.lineCount(forContainer: "container-b"),
            3000,
            "Container B should retain all entries (under cap)"
        )

        // Verify independence: clearing A does not affect B
        buffer.clear(containerId: "container-a")
        XCTAssertEqual(buffer.lineCount(forContainer: "container-a"), 0)
        XCTAssertEqual(buffer.lineCount(forContainer: "container-b"), 3000)
    }

    // MARK: - Real Docker Tests

    func testRealDockerLogBurstIntoCappedBuffer() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let runID = "log-burst-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        let descriptor = FixtureDescriptor(
            key: "log-producer",
            image: "alpine:3.20",
            command: ["sh", "-c", "for i in $(seq 1 500); do echo \"burst-line-$i\"; done; sleep 3600"],
            environment: [:]
        )

        let handles: [FixtureHandle]
        do {
            handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [descriptor],
                desiredStates: [.running]
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        let containerId = handles[0].containerId

        // Allow time for log production
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let adapter = CLIEngineAdapter()
        let options = LogStreamOptions(
            since: nil,
            tail: 500,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        let lineCap = 200
        let policy = LogBufferPolicy(
            maxLinesPerContainer: lineCap,
            maxBytesPerContainer: 1_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        for try await entry in adapter.streamLogs(id: containerId, options: options) {
            buffer.append(entry)
        }

        let storedCount = buffer.lineCount(forContainer: containerId)
        XCTAssertGreaterThan(storedCount, 0, "Should have buffered some log entries")
        XCTAssertLessThanOrEqual(
            storedCount,
            lineCap,
            "Buffer should respect the line cap"
        )
    }

    func testRealDockerLogBurstSearchCorrectness() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let runID = "log-search-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        let descriptor = FixtureDescriptor(
            key: "search-producer",
            image: "alpine:3.20",
            command: ["sh", "-c", """
            for i in $(seq 1 100); do
                if [ $((i % 10)) -eq 0 ]; then
                    echo "READY-MARKER line $i"
                else
                    echo "normal log line $i"
                fi
            done
            sleep 3600
            """],
            environment: [:]
        )

        let handles: [FixtureHandle]
        do {
            handles = try await orchestrator.createFixtures(
                runID: runID,
                descriptors: [descriptor],
                desiredStates: [.running]
            )
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        let containerId = handles[0].containerId
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let adapter = CLIEngineAdapter()
        let options = LogStreamOptions(
            since: nil,
            tail: 200,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        let policy = LogBufferPolicy(
            maxLinesPerContainer: 1000,
            maxBytesPerContainer: 1_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)
        let searchEngine = LogSearchEngine()

        for try await entry in adapter.streamLogs(id: containerId, options: options) {
            buffer.append(entry)
        }

        let query = LogSearchQuery(
            pattern: "READY-MARKER",
            matchMode: .substring,
            containerFilter: containerId
        )
        let results = searchEngine.search(in: buffer, query: query)

        // Should find approximately 10 markers (100 lines / 10)
        XCTAssertGreaterThan(results.count, 0, "Should find READY-MARKER lines in real Docker logs")
        XCTAssertLessThanOrEqual(results.count, 15, "Should not have more markers than expected")

        for result in results {
            XCTAssertTrue(result.entry.message.contains("READY-MARKER"))
        }
    }
}
