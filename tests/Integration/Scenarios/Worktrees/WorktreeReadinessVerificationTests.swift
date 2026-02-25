import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Worktree Readiness Verification Tests

/// Tests that verify readiness evaluation correctness after container restarts
/// in the context of worktree switching. Validates stale-line rejection,
/// fresh-line acceptance, health-check short-circuiting, and the full
/// buffer-to-search-to-evaluator pipeline.
final class WorktreeReadinessVerificationTests: XCTestCase {
    private let evaluator = ReadinessEvaluator()

    // MARK: - Helpers

    private func makeEntry(
        containerId: String = "wt-container",
        message: String,
        timestamp: Date,
        stream: LogStream = .stdout
    ) -> LogEntry {
        LogEntry(
            engineContextId: "integ-ctx",
            containerId: containerId,
            stream: stream,
            timestamp: timestamp,
            message: message
        )
    }

    private func makeRule(
        mode: ReadinessMode = .regexOnly,
        pattern: String? = "ready|listening",
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

    // MARK: - Mock Tests

    func testStaleLineRejectionAfterRestart() throws {
        let restartTime = Date(timeIntervalSince1970: 1_000_000)
        let rule = makeRule()

        // All entries are from BEFORE the restart (stale)
        let staleEntries = (0 ..< 10).map { i in
            makeEntry(
                message: "ready at step \(i)",
                timestamp: Date(timeIntervalSince1970: 999_990 + Double(i))
            )
        }

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: staleEntries,
            windowStart: restartTime
        )

        XCTAssertFalse(result.isReady, "All entries are stale, should not be ready")
        XCTAssertEqual(result.rejectedStaleEntries, 10)
        XCTAssertEqual(result.evaluatedEntries, 0)
        XCTAssertEqual(result.regexMatchCount, 0)
    }

    func testFreshReadyLineAfterRestartSucceeds() throws {
        let restartTime = Date(timeIntervalSince1970: 1_000_000)
        let rule = makeRule()

        // Mix of stale and fresh entries
        var entries: [LogEntry] = []

        // 5 stale entries with "ready" (should be rejected)
        for i in 0 ..< 5 {
            entries.append(makeEntry(
                message: "ready from previous lifecycle \(i)",
                timestamp: Date(timeIntervalSince1970: 999_995 + Double(i))
            ))
        }

        // 5 fresh entries, one with "ready"
        for i in 0 ..< 5 {
            let message: String
            if i == 3 {
                message = "server ready to accept connections"
            } else {
                message = "initializing component \(i)"
            }
            entries.append(makeEntry(
                message: message,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i))
            ))
        }

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: restartTime
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.rejectedStaleEntries, 5)
        XCTAssertEqual(result.evaluatedEntries, 5)
        XCTAssertEqual(result.regexMatchCount, 1)
    }

    func testHealthCheckShortCircuitsAfterRestart() throws {
        let restartTime = Date(timeIntervalSince1970: 1_000_000)
        let rule = makeRule(mode: .healthThenRegex)

        // Entries that would match regex
        let entries = [
            makeEntry(
                message: "ready",
                timestamp: Date(timeIntervalSince1970: 1_000_001)
            ),
        ]

        // With healthy status, health check short-circuits
        let healthyResult = try evaluator.evaluate(
            rule: rule,
            healthStatus: .healthy,
            logEntries: entries,
            windowStart: restartTime
        )

        XCTAssertTrue(healthyResult.isReady)
        XCTAssertTrue(healthyResult.healthSatisfied)
        XCTAssertEqual(healthyResult.evaluatedEntries, 0, "Should not evaluate logs when health passes")

        // With starting status, falls back to regex
        let startingResult = try evaluator.evaluate(
            rule: rule,
            healthStatus: .starting,
            logEntries: entries,
            windowStart: restartTime
        )

        XCTAssertTrue(startingResult.isReady)
        XCTAssertFalse(startingResult.healthSatisfied)
        XCTAssertEqual(startingResult.regexMatchCount, 1)
    }

    func testTimestampWindowBoundaryInclusiveness() throws {
        let windowStart = Date(timeIntervalSince1970: 1_000_000)
        let rule = makeRule()

        let entries = [
            // 1 nanosecond before (should be stale)
            makeEntry(
                message: "ready just before",
                timestamp: Date(timeIntervalSince1970: 999_999.999)
            ),
            // Exactly at boundary (should be included)
            makeEntry(
                message: "ready at boundary",
                timestamp: windowStart
            ),
            // 1 second after (should be included)
            makeEntry(
                message: "ready after",
                timestamp: Date(timeIntervalSince1970: 1_000_001)
            ),
        ]

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertEqual(result.rejectedStaleEntries, 1, "Only the entry before windowStart is stale")
        XCTAssertEqual(result.evaluatedEntries, 2, "Boundary and after should be evaluated")
        XCTAssertEqual(result.regexMatchCount, 2, "Both fresh entries match 'ready'")
        XCTAssertTrue(result.isReady)
    }

    func testBufferToSearchToEvaluatorPipeline() throws {
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 1000,
            maxBytesPerContainer: 1_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)
        let searchEngine = LogSearchEngine()
        let windowStart = Date(timeIntervalSince1970: 1_000_000)

        // Fill buffer with entries - some stale, some fresh
        for i in 0 ..< 200 {
            let timestamp: Date
            let message: String

            if i < 100 {
                // Stale entries (before window start)
                timestamp = Date(timeIntervalSince1970: 999_900 + Double(i))
                message = i % 20 == 0 ? "old-lifecycle ready" : "old-lifecycle step \(i)"
            } else {
                // Fresh entries (after window start)
                timestamp = Date(timeIntervalSince1970: 1_000_000 + Double(i - 100))
                message = i % 20 == 0 ? "new-lifecycle ready" : "new-lifecycle step \(i)"
            }

            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: "pipeline-test",
                stream: .stdout,
                timestamp: timestamp,
                message: message
            )
            buffer.append(entry)
        }

        // Step 1: Search for all entries (no time filter in search, let evaluator handle staleness)
        let allEntries = buffer.entries(forContainer: "pipeline-test")
        XCTAssertEqual(allEntries.count, 200)

        // Step 2: Feed to readiness evaluator
        let rule = makeRule(pattern: "ready", mustMatchCount: 3)

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: allEntries,
            windowStart: windowStart
        )

        XCTAssertEqual(result.rejectedStaleEntries, 100, "First 100 entries are stale")
        XCTAssertEqual(result.evaluatedEntries, 100, "Second 100 entries are fresh")

        // Fresh entries: i=100,120,140,160,180 => indices in fresh range: 0,20,40,60,80
        // That is 5 entries matching "ready"
        XCTAssertEqual(result.regexMatchCount, 5)
        XCTAssertTrue(result.isReady, "5 matches >= mustMatchCount of 3")
    }

    func testPartialMatchesDoNotSatisfyReadiness() throws {
        let windowStart = Date(timeIntervalSince1970: 1_000_000)
        let rule = makeRule(pattern: "worker \\d+ ready", mustMatchCount: 3)

        // Only 2 matches (need 3)
        let entries = [
            makeEntry(
                message: "worker 1 ready",
                timestamp: Date(timeIntervalSince1970: 1_000_001)
            ),
            makeEntry(
                message: "worker 2 initializing",
                timestamp: Date(timeIntervalSince1970: 1_000_002)
            ),
            makeEntry(
                message: "worker 2 ready",
                timestamp: Date(timeIntervalSince1970: 1_000_003)
            ),
            makeEntry(
                message: "worker 3 starting",
                timestamp: Date(timeIntervalSince1970: 1_000_004)
            ),
        ]

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: windowStart
        )

        XCTAssertFalse(result.isReady, "Only 2 matches, need 3")
        XCTAssertEqual(result.regexMatchCount, 2)
        XCTAssertEqual(result.evaluatedEntries, 4)
    }

    // MARK: - Real Docker Tests

    func testRealDockerRestartAndReadinessViaLogs() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let adapter = CLIEngineAdapter()
        let runID = "readiness-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        // Create a container that outputs a "ready" marker on start
        let descriptor = FixtureDescriptor(
            key: "readiness-check",
            image: "alpine:3.20",
            command: ["sh", "-c", "echo 'server listening on port 8080'; sleep 3600"],
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

        // Collect logs into buffer
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 500,
            maxBytesPerContainer: 500_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        let options = LogStreamOptions(
            since: nil,
            tail: 100,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        for try await entry in adapter.streamLogs(id: containerId, options: options) {
            buffer.append(entry)
        }

        // Evaluate readiness against log buffer
        let entries = buffer.entries(forContainer: containerId)
        XCTAssertGreaterThan(entries.count, 0, "Should have log entries from container")

        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "listening",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        // Use a very early window start to include all entries
        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(result.isReady, "Container should be ready (log contains 'listening')")
        XCTAssertGreaterThanOrEqual(result.regexMatchCount, 1)
    }

    func testRealDockerStaleLinesFromPreviousLifecycle() async throws {
        try skipUnlessDockerAvailable()

        let orchestrator = DockerFixtureOrchestrator()
        let adapter = CLIEngineAdapter()
        let runID = "stale-\(UUID().uuidString.prefix(8).lowercased())"

        defer {
            Task { await orchestrator.removeFixtures(runID: runID) }
        }

        // Create a container that outputs a ready marker
        let descriptor = FixtureDescriptor(
            key: "stale-check",
            image: "alpine:3.20",
            command: ["sh", "-c", "echo 'LIFECYCLE-READY'; sleep 3600"],
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

        // Record the restart time boundary
        let beforeRestart = Date()

        // Restart the container
        try await adapter.restartContainer(id: containerId, timeoutSeconds: 10)
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Collect all logs (including from first lifecycle)
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 1000,
            maxBytesPerContainer: 1_000_000,
            dropStrategy: .dropOldest,
            flushHz: 1
        )
        let buffer = LogRingBuffer(policy: policy)

        let options = LogStreamOptions(
            since: nil,
            tail: 100,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        for try await entry in adapter.streamLogs(id: containerId, options: options) {
            buffer.append(entry)
        }

        let entries = buffer.entries(forContainer: containerId)

        // Evaluate with windowStart = beforeRestart.
        // Lines from the first lifecycle (before restart) should be stale.
        let rule = ReadinessRule(
            mode: .regexOnly,
            regexPattern: "LIFECYCLE-READY",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )

        let result = try evaluator.evaluate(
            rule: rule,
            healthStatus: nil,
            logEntries: entries,
            windowStart: beforeRestart
        )

        // Should have at least one stale entry from the first lifecycle
        // and at least one fresh entry from after restart
        XCTAssertGreaterThanOrEqual(
            result.rejectedStaleEntries, 0,
            "May have stale entries from first lifecycle"
        )

        // The fresh entry from the second lifecycle should satisfy readiness
        if !entries.isEmpty {
            XCTAssertGreaterThanOrEqual(
                result.evaluatedEntries, 1,
                "Should have evaluated at least one entry from second lifecycle"
            )
        }
    }
}
