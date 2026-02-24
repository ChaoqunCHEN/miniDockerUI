import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Mock Command Runner

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

// MARK: - Tests

final class CLIEngineAdapterTests: XCTestCase {
    private var mock: MockCommandRunner!
    private var adapter: CLIEngineAdapter!

    override func setUp() {
        mock = MockCommandRunner()
        adapter = CLIEngineAdapter(
            dockerPath: "/usr/local/bin/docker",
            engineContextId: "test-ctx",
            runner: mock
        )
    }

    // MARK: - listContainers

    func testListContainersBuildsCorrectArgs() async throws {
        mock.runHandler = { _ in
            CommandResult(exitCode: 0)
        }
        _ = try await adapter.listContainers()
        let req = mock.capturedRunRequests.first
        XCTAssertEqual(req?.executablePath, "/usr/local/bin/docker")
        XCTAssertEqual(req?.arguments, ["ps", "-a", "--format", "json", "--no-trunc"])
    }

    func testListContainersParsesNDJSON() async throws {
        let json1 = """
        {"ID":"abc123","Names":"web","Image":"nginx","Status":"Up 2 hours","Labels":"","CreatedAt":"2026-01-01 00:00:00 +0000 UTC"}
        """
        let json2 = """
        {"ID":"def456","Names":"db","Image":"postgres","Status":"Exited (0) 1 hour ago","Labels":"","CreatedAt":"2026-01-01 00:00:00 +0000 UTC"}
        """
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 0,
                stdout: "\(json1)\n\(json2)\n".data(using: .utf8)!
            )
        }
        let containers = try await adapter.listContainers()
        XCTAssertEqual(containers.count, 2)
        XCTAssertEqual(containers[0].id, "abc123")
        XCTAssertEqual(containers[0].name, "web")
        XCTAssertEqual(containers[0].engineContextId, "test-ctx")
        XCTAssertEqual(containers[1].id, "def456")
        XCTAssertEqual(containers[1].name, "db")
    }

    func testListContainersEmptyOutput() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        let containers = try await adapter.listContainers()
        XCTAssertEqual(containers.count, 0)
    }

    func testListContainersThrowsOnNonZeroExit() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 1,
                stderr: "daemon not running".data(using: .utf8)!
            )
        }
        do {
            _ = try await adapter.listContainers()
            XCTFail("Expected error")
        } catch let error as CoreError {
            if case let .processNonZeroExit(_, exitCode, stderr) = error {
                XCTAssertEqual(exitCode, 1)
                XCTAssertEqual(stderr, "daemon not running")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - inspectContainer

    func testInspectContainerBuildsCorrectArgs() async throws {
        let inspectJSON = """
        [{"Id":"abc123","Name":"/web","Config":{"Image":"nginx","Labels":{}},"State":{"Status":"running"},"Mounts":[],"NetworkSettings":{"Ports":{},"Networks":{}},"HostConfig":{"NetworkMode":"bridge"}}]
        """
        mock.runHandler = { _ in
            CommandResult(exitCode: 0, stdout: inspectJSON.data(using: .utf8)!)
        }
        _ = try await adapter.inspectContainer(id: "abc123")
        let req = mock.capturedRunRequests.first
        XCTAssertEqual(req?.arguments, ["inspect", "abc123"])
    }

    func testInspectContainerParsesOutput() async throws {
        let inspectJSON = """
        [{"Id":"abc123","Name":"/my-container","Config":{"Image":"nginx:latest","Labels":{"app":"web"}},"State":{"Status":"running","StartedAt":"2026-01-15T10:30:00Z"},"Mounts":[],"NetworkSettings":{"Ports":{},"Networks":{"bridge":{"IPAddress":"172.17.0.2"}}},"HostConfig":{"NetworkMode":"bridge"}}]
        """
        mock.runHandler = { _ in
            CommandResult(exitCode: 0, stdout: inspectJSON.data(using: .utf8)!)
        }
        let detail = try await adapter.inspectContainer(id: "abc123")
        XCTAssertEqual(detail.summary.id, "abc123")
        XCTAssertEqual(detail.summary.name, "my-container")
        XCTAssertEqual(detail.summary.image, "nginx:latest")
        XCTAssertEqual(detail.summary.engineContextId, "test-ctx")
        XCTAssertEqual(detail.networkSettings.networkMode, "bridge")
    }

    // MARK: - startContainer

    func testStartContainerBuildsCorrectArgs() async throws {
        try await adapter.startContainer(id: "abc123")
        let req = mock.capturedRunCheckedRequests.first
        XCTAssertEqual(req?.arguments, ["start", "abc123"])
    }

    // MARK: - stopContainer

    func testStopContainerWithoutTimeout() async throws {
        try await adapter.stopContainer(id: "abc123", timeoutSeconds: nil)
        let req = mock.capturedRunCheckedRequests.first
        XCTAssertEqual(req?.arguments, ["stop", "abc123"])
    }

    func testStopContainerWithTimeout() async throws {
        try await adapter.stopContainer(id: "abc123", timeoutSeconds: 10)
        let req = mock.capturedRunCheckedRequests.first
        XCTAssertEqual(req?.arguments, ["stop", "--time", "10", "abc123"])
    }

    // MARK: - restartContainer

    func testRestartContainerBuildsCorrectArgs() async throws {
        try await adapter.restartContainer(id: "abc123", timeoutSeconds: nil)
        let req = mock.capturedRunCheckedRequests.first
        XCTAssertEqual(req?.arguments, ["restart", "abc123"])
    }

    func testRestartContainerWithTimeout() async throws {
        try await adapter.restartContainer(id: "abc123", timeoutSeconds: 5)
        let req = mock.capturedRunCheckedRequests.first
        XCTAssertEqual(req?.arguments, ["restart", "--time", "5", "abc123"])
    }

    // MARK: - streamEvents

    func testStreamEventsBuildsCorrectArgs() async throws {
        mock.streamHandler = { _ in
            AsyncThrowingStream { $0.finish() }
        }
        let stream = adapter.streamEvents(since: nil)
        for try await _ in stream {}
        let req = mock.capturedStreamRequests.first
        XCTAssertEqual(req?.arguments, ["events", "--format", "json"])
    }

    func testStreamEventsWithSince() async throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        mock.streamHandler = { _ in
            AsyncThrowingStream { $0.finish() }
        }
        let stream = adapter.streamEvents(since: since)
        for try await _ in stream {}
        let req = mock.capturedStreamRequests.first
        XCTAssertEqual(req?.arguments, ["events", "--format", "json", "--since", "1700000000"])
    }

    func testStreamEventsYieldsEnvelopes() async throws {
        let eventJSON = """
        {"Action":"start","Type":"container","Actor":{"ID":"abc123","Attributes":{"name":"web"}},"time":1700000000,"timeNano":1700000000000000000}
        """
        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(eventJSON.appending("\n").data(using: .utf8)!)
                continuation.finish()
            }
        }
        var envelopes: [EventEnvelope] = []
        for try await envelope in adapter.streamEvents(since: nil) {
            envelopes.append(envelope)
        }
        XCTAssertEqual(envelopes.count, 1)
        XCTAssertEqual(envelopes[0].action, "start")
        XCTAssertEqual(envelopes[0].containerId, "abc123")
        XCTAssertEqual(envelopes[0].sequence, 0)
    }

    // MARK: - streamLogs

    func testStreamLogsBuildsCorrectArgs() async throws {
        mock.streamHandler = { _ in
            AsyncThrowingStream { $0.finish() }
        }
        let options = LogStreamOptions(
            since: nil,
            tail: 100,
            includeStdout: true,
            includeStderr: true,
            timestamps: true,
            follow: true
        )
        let stream = adapter.streamLogs(id: "abc123", options: options)
        for try await _ in stream {}
        let req = mock.capturedStreamRequests.first
        XCTAssertNotNil(req)
        XCTAssertTrue(try XCTUnwrap(req?.arguments.contains("-t")))
        XCTAssertTrue(try XCTUnwrap(req?.arguments.contains("-f")))
        XCTAssertTrue(try XCTUnwrap(req?.arguments.contains("--tail")))
        XCTAssertTrue(try XCTUnwrap(req?.arguments.contains("100")))
        XCTAssertTrue(try XCTUnwrap(req?.arguments.contains("abc123")))
    }

    func testStreamLogsYieldsEntries() async throws {
        let logLine = "2026-01-15T10:30:00.123456789Z Hello from container\n"
        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(logLine.data(using: .utf8)!)
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
        for try await entry in adapter.streamLogs(id: "abc123", options: options) {
            entries.append(entry)
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].containerId, "abc123")
        XCTAssertEqual(entries[0].engineContextId, "test-ctx")
        XCTAssertEqual(entries[0].message, "Hello from container")
    }

    func testStreamLogsHandlesChunkedData() async throws {
        let part1 = "2026-01-15T10:30:00.000Z First"
        let part2 = " line\n2026-01-15T10:30:01.000Z Second line\n"
        mock.streamHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(part1.data(using: .utf8)!)
                continuation.yield(part2.data(using: .utf8)!)
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
        for try await entry in adapter.streamLogs(id: "c1", options: options) {
            entries.append(entry)
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].message, "First line")
        XCTAssertEqual(entries[1].message, "Second line")
    }
}
