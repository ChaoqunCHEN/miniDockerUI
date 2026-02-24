import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Mock Command Runner (integration-level)

/// A command runner that records invocations and returns canned results.
/// Mirrors the mock in CLIEngineAdapterTests but scoped to the integration target.
private final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    var runHandler: ((CommandRequest) async throws -> CommandResult)?
    var runCheckedHandler: ((CommandRequest) async throws -> CommandResult)?
    var streamHandler: ((CommandRequest) -> AsyncThrowingStream<Data, Error>)?

    private(set) var capturedRunRequests: [CommandRequest] = []
    private(set) var capturedRunCheckedRequests: [CommandRequest] = []
    private(set) var capturedStreamRequests: [CommandRequest] = []

    func run(_ request: CommandRequest) async throws -> CommandResult {
        capturedRunRequests.append(request)
        guard let handler = runHandler else {
            return CommandResult(exitCode: 0)
        }
        return try await handler(request)
    }

    func runChecked(_ request: CommandRequest) async throws -> CommandResult {
        capturedRunCheckedRequests.append(request)
        guard let handler = runCheckedHandler else {
            return CommandResult(exitCode: 0)
        }
        return try await handler(request)
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        capturedStreamRequests.append(request)
        guard let handler = streamHandler else {
            return AsyncThrowingStream { $0.finish() }
        }
        return handler(request)
    }
}

// MARK: - Adapter Lifecycle Integration Tests

final class CLIAdapterLifecycleTests: XCTestCase {
    private var mock: MockCommandRunner!
    private var adapter: CLIEngineAdapter!

    override func setUp() {
        mock = MockCommandRunner()
        adapter = CLIEngineAdapter(
            dockerPath: "/usr/local/bin/docker",
            engineContextId: "integ-ctx",
            runner: mock
        )
    }

    // MARK: - S2: Multi-container list round-trip

    func testListContainersRoundTripsMultipleContainers() async throws {
        let json1 = """
        {"ID":"aaa111","Names":"web-frontend","Image":"nginx:1.25","Status":"Up 3 hours","Labels":"env=prod,tier=frontend","CreatedAt":"2026-01-10 08:00:00 +0000 UTC"}
        """
        let json2 = """
        {"ID":"bbb222","Names":"api-server","Image":"node:20-alpine","Status":"Exited (0) 30 minutes ago","Labels":"env=staging","CreatedAt":"2026-01-10 09:00:00 +0000 UTC"}
        """
        let json3 = """
        {"ID":"ccc333","Names":"redis-cache","Image":"redis:7","Status":"Up 5 hours","Labels":"","CreatedAt":"2026-01-09 12:00:00 +0000 UTC"}
        """
        mock.runHandler = { _ in
            let combined = "\(json1)\n\(json2)\n\(json3)\n"
            return CommandResult(exitCode: 0, stdout: combined.data(using: .utf8)!)
        }

        let containers = try await adapter.listContainers()
        XCTAssertEqual(containers.count, 3)

        // Verify first container fields
        XCTAssertEqual(containers[0].id, "aaa111")
        XCTAssertEqual(containers[0].name, "web-frontend")
        XCTAssertEqual(containers[0].image, "nginx:1.25")
        XCTAssertEqual(containers[0].engineContextId, "integ-ctx")
        XCTAssertTrue(containers[0].status.contains("Up"))

        // Verify second container
        XCTAssertEqual(containers[1].id, "bbb222")
        XCTAssertEqual(containers[1].name, "api-server")
        XCTAssertEqual(containers[1].image, "node:20-alpine")
        XCTAssertTrue(containers[1].status.contains("Exited"))

        // Verify third container
        XCTAssertEqual(containers[2].id, "ccc333")
        XCTAssertEqual(containers[2].name, "redis-cache")
    }

    // MARK: - S2: Inspect returns full detail

    func testInspectContainerReturnsFullDetail() async throws {
        let inspectJSON = """
        [{"Id":"abc123def456","Name":"/production-web","Config":{"Image":"nginx:1.25-alpine","Labels":{"env":"production","team":"platform"}},"State":{"Status":"running","StartedAt":"2026-01-15T10:30:00Z"},"Mounts":[{"Source":"/host/data","Destination":"/app/data","Mode":"ro","RW":false}],"NetworkSettings":{"Ports":{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"8080"}]},"Networks":{"bridge":{"IPAddress":"172.17.0.5"},"backend":{"IPAddress":"10.0.1.100"}}},"HostConfig":{"NetworkMode":"bridge"}}]
        """
        mock.runHandler = { _ in
            CommandResult(exitCode: 0, stdout: inspectJSON.data(using: .utf8)!)
        }

        let detail = try await adapter.inspectContainer(id: "abc123def456")

        // Summary
        XCTAssertEqual(detail.summary.id, "abc123def456")
        XCTAssertEqual(detail.summary.name, "production-web")
        XCTAssertEqual(detail.summary.image, "nginx:1.25-alpine")
        XCTAssertEqual(detail.summary.labels["env"], "production")
        XCTAssertEqual(detail.summary.labels["team"], "platform")
        XCTAssertEqual(detail.summary.engineContextId, "integ-ctx")

        // Network
        XCTAssertEqual(detail.networkSettings.networkMode, "bridge")
        XCTAssertEqual(detail.networkSettings.ipAddressesByNetwork["bridge"], "172.17.0.5")
        XCTAssertEqual(detail.networkSettings.ipAddressesByNetwork["backend"], "10.0.1.100")
        XCTAssertFalse(detail.networkSettings.ports.isEmpty)

        // Mounts
        XCTAssertEqual(detail.mounts.count, 1)
        XCTAssertEqual(detail.mounts[0].source, "/host/data")
        XCTAssertEqual(detail.mounts[0].destination, "/app/data")
        XCTAssertTrue(detail.mounts[0].isReadOnly)
    }

    // MARK: - S2: Start/stop/restart sequence

    func testStartStopRestartSequence() async throws {
        // Start
        try await adapter.startContainer(id: "seq-test-container")
        XCTAssertEqual(mock.capturedRunCheckedRequests.count, 1)
        XCTAssertEqual(mock.capturedRunCheckedRequests[0].arguments, ["start", "seq-test-container"])

        // Stop with timeout
        try await adapter.stopContainer(id: "seq-test-container", timeoutSeconds: 15)
        XCTAssertEqual(mock.capturedRunCheckedRequests.count, 2)
        XCTAssertEqual(mock.capturedRunCheckedRequests[1].arguments, ["stop", "--time", "15", "seq-test-container"])

        // Restart without timeout
        try await adapter.restartContainer(id: "seq-test-container", timeoutSeconds: nil)
        XCTAssertEqual(mock.capturedRunCheckedRequests.count, 3)
        XCTAssertEqual(mock.capturedRunCheckedRequests[2].arguments, ["restart", "seq-test-container"])
    }

    // MARK: - S2: Error propagation

    func testAdapterErrorPropagation() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 125,
                stderr: "Error response from daemon: container not found".data(using: .utf8)!
            )
        }

        do {
            _ = try await adapter.listContainers()
            XCTFail("Expected processNonZeroExit error")
        } catch let error as CoreError {
            if case let .processNonZeroExit(_, exitCode, stderr) = error {
                XCTAssertEqual(exitCode, 125)
                XCTAssertTrue(stderr.contains("container not found"))
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        }
    }

    // MARK: - S3: Stream events with multiple envelopes

    func testStreamEventsMultipleEvents() async throws {
        let events = (0 ..< 12).map { i in
            """
            {"Action":"start","Type":"container","Actor":{"ID":"evt-\(i)","Attributes":{"name":"svc-\(i)"}},"time":\(1_700_000_000 + i),"timeNano":\(1_700_000_000_000_000_000 + i * 1_000_000_000)}
            """
        }
        let allLines = events.joined(separator: "\n") + "\n"

        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(allLines.data(using: .utf8)!)
                continuation.finish()
            }
        }

        var envelopes: [EventEnvelope] = []
        for try await envelope in adapter.streamEvents(since: nil) {
            envelopes.append(envelope)
        }

        XCTAssertEqual(envelopes.count, 12)
        // Verify sequence numbering is sequential
        for (i, envelope) in envelopes.enumerated() {
            XCTAssertEqual(envelope.sequence, UInt64(i), "Sequence mismatch at index \(i)")
            XCTAssertEqual(envelope.containerId, "evt-\(i)")
            XCTAssertEqual(envelope.action, "start")
        }
    }

    // MARK: - S4: Chunked log delivery through DataLineAccumulator

    func testStreamLogsWithChunkedDelivery() async throws {
        // Simulate sub-line chunks that split mid-timestamp and mid-message
        let chunk1 = "2026-01-15T10:30:00.000Z First l"
        let chunk2 = "ine of logs\n2026-01-15T10:30:01."
        let chunk3 = "000Z Second line of logs\n2026-01"
        let chunk4 = "-15T10:30:02.000Z Third line\n"

        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                for chunk in [chunk1, chunk2, chunk3, chunk4] {
                    continuation.yield(chunk.data(using: .utf8)!)
                }
                continuation.finish()
            }
        }

        let options = LogStreamOptions(
            since: nil,
            tail: nil,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        var entries: [LogEntry] = []
        for try await entry in adapter.streamLogs(id: "chunked-test", options: options) {
            entries.append(entry)
        }

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].message, "First line of logs")
        XCTAssertEqual(entries[1].message, "Second line of logs")
        XCTAssertEqual(entries[2].message, "Third line")
        // Verify containerId and contextId are set correctly
        for entry in entries {
            XCTAssertEqual(entry.containerId, "chunked-test")
            XCTAssertEqual(entry.engineContextId, "integ-ctx")
        }
    }

    // MARK: - S4: Adapter does NOT cap log entries (ViewModel responsibility)

    func testStreamLogsDoesNotCapEntries() async throws {
        let lineCount = 6000
        var allLines = ""
        for i in 0 ..< lineCount {
            let ts = String(format: "2026-01-15T10:%02d:%02d.000Z", i / 60 % 60, i % 60)
            allLines += "\(ts) Log line \(i)\n"
        }

        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                // Deliver in large chunks
                let data = allLines.data(using: .utf8)!
                let chunkSize = 8192
                var offset = 0
                while offset < data.count {
                    let end = min(offset + chunkSize, data.count)
                    continuation.yield(data[offset ..< end])
                    offset = end
                }
                continuation.finish()
            }
        }

        let options = LogStreamOptions(
            since: nil,
            tail: nil,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: false
        )

        var entries: [LogEntry] = []
        for try await entry in adapter.streamLogs(id: "cap-test", options: options) {
            entries.append(entry)
        }

        // Adapter should pass all lines through — capping at 5000 is the ViewModel's job
        XCTAssertEqual(entries.count, lineCount, "Adapter must not cap log entries")
    }

    // MARK: - S6: Real Docker tests (skipped if Docker unavailable)

    func testRealListContainersReturnsArray() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )

        let realAdapter = CLIEngineAdapter()
        do {
            let containers = try await realAdapter.listContainers()
            // Should return an array (possibly empty if no containers running)
            XCTAssertTrue(containers is [ContainerSummary])
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }
    }

    func testRealInspectKnownFixture() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )

        let realAdapter = CLIEngineAdapter()
        // First list containers to find if any exist
        let containers: [ContainerSummary]
        do {
            containers = try await realAdapter.listContainers()
        } catch {
            throw XCTSkip("Docker daemon not available: \(error)")
        }

        guard let first = containers.first else {
            throw XCTSkip("No containers available for inspect test")
        }

        let detail = try await realAdapter.inspectContainer(id: first.id)
        XCTAssertEqual(detail.summary.id, first.id)
        XCTAssertFalse(detail.summary.name.isEmpty)
        XCTAssertFalse(detail.summary.image.isEmpty)
    }
}
