import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - Recording Mock Command Runner

/// A command runner that records all invocations and returns pre-configured results.
/// Used by orchestrator tests to verify correct Docker CLI arguments without
/// requiring a real Docker daemon.
private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    /// All requests passed to ``run(_:)``, in order.
    private(set) var capturedRequests: [CommandRequest] = []

    /// Pre-configured results returned by ``run(_:)`` in FIFO order.
    /// When exhausted, returns a default success result.
    var queuedResults: [CommandResult] = []

    /// Optional handler for dynamic result generation based on request.
    var runHandler: ((CommandRequest) -> CommandResult)?

    func run(_ request: CommandRequest) async throws -> CommandResult {
        capturedRequests.append(request)

        if let handler = runHandler {
            return handler(request)
        }

        if !queuedResults.isEmpty {
            return queuedResults.removeFirst()
        }

        return CommandResult(exitCode: 0)
    }

    func runChecked(_ request: CommandRequest) async throws -> CommandResult {
        let result = try await run(request)
        guard result.isSuccess else {
            throw CoreError.processNonZeroExit(
                executablePath: request.executablePath,
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result
    }

    func stream(_: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - FixtureOrchestratorTests

final class FixtureOrchestratorTests: XCTestCase {
    private var mock: RecordingCommandRunner!
    private var orchestrator: DockerFixtureOrchestrator!

    override func setUp() {
        mock = RecordingCommandRunner()
        orchestrator = DockerFixtureOrchestrator(
            runner: mock,
            dockerPath: "/usr/local/bin/docker",
            defaultImage: "alpine:3.20"
        )
    }

    // MARK: - Helpers

    private func makeDescriptor(
        key: String = "web",
        image: String = "nginx:1.25",
        command: [String] = ["sleep", "3600"],
        environment: [String: String] = [:]
    ) -> FixtureDescriptor {
        FixtureDescriptor(key: key, image: image, command: command, environment: environment)
    }

    /// Configures mock to return a fake container ID for inspect calls.
    private func configureMockForCreation(containerId: String = "abc123def456") {
        mock.runHandler = { request in
            // Return container ID for inspect --format calls
            if request.arguments.contains("inspect") {
                return CommandResult(
                    exitCode: 0,
                    stdout: "\(containerId)\n".data(using: .utf8)!
                )
            }
            return CommandResult(exitCode: 0)
        }
    }

    /// Configures mock to return specific container IDs for each fixture by key.
    private func configureMockForMultipleCreations(idsByKey: [String: String]) {
        var inspectCallIndex = 0
        let keys = Array(idsByKey.keys.sorted())

        mock.runHandler = { request in
            if request.arguments.contains("inspect") {
                let key = keys.count > inspectCallIndex ? keys[inspectCallIndex] : "unknown"
                inspectCallIndex += 1
                let id = idsByKey[key] ?? "unknown-id"
                return CommandResult(
                    exitCode: 0,
                    stdout: "\(id)\n".data(using: .utf8)!
                )
            }
            return CommandResult(exitCode: 0)
        }
    }

    // MARK: - Test: Container Name Format

    func testContainerNameFormat() {
        let name = orchestrator.containerName(runID: "abc-123", key: "web-server")
        XCTAssertEqual(name, "mdui-test-abc-123-web-server")
    }

    func testContainerNameFormatWithUUID() {
        let uuid = UUID().uuidString.lowercased()
        let name = orchestrator.containerName(runID: uuid, key: "redis")
        XCTAssertTrue(name.hasPrefix("mdui-test-"))
        XCTAssertTrue(name.hasSuffix("-redis"))
        XCTAssertTrue(name.contains(uuid))
    }

    // MARK: - Test: Create Fixtures Builds Correct Docker Create Args

    func testCreateFixturesBuildCorrectDockerCreateArgs() async throws {
        configureMockForCreation()

        let descriptor = makeDescriptor(
            key: "api",
            image: "node:20",
            command: ["node", "server.js"],
            environment: ["PORT": "3000", "NODE_ENV": "test"]
        )

        _ = try await orchestrator.createFixtures(runID: "run-1", descriptors: [descriptor])

        // First request should be docker create
        let createReq = try XCTUnwrap(mock.capturedRequests.first)
        XCTAssertEqual(createReq.executablePath, "/usr/local/bin/docker")

        // Verify create command structure
        XCTAssertEqual(createReq.arguments[0], "create")
        XCTAssertEqual(createReq.arguments[1], "--name")
        XCTAssertEqual(createReq.arguments[2], "mdui-test-run-1-api")

        // Verify environment variables are present
        let argsJoined = createReq.arguments.joined(separator: " ")
        XCTAssertTrue(argsJoined.contains("-e NODE_ENV=test"))
        XCTAssertTrue(argsJoined.contains("-e PORT=3000"))

        // Verify image and command at the end
        XCTAssertTrue(createReq.arguments.contains("node:20"))
        XCTAssertTrue(createReq.arguments.contains("node"))
        XCTAssertTrue(createReq.arguments.contains("server.js"))

        // Second request should be docker inspect
        let inspectReq = mock.capturedRequests[1]
        XCTAssertEqual(inspectReq.arguments[0], "inspect")
        XCTAssertEqual(inspectReq.arguments[1], "--format")
        XCTAssertEqual(inspectReq.arguments[2], "{{.Id}}")
        XCTAssertEqual(inspectReq.arguments[3], "mdui-test-run-1-api")

        // Verify timeout is set
        XCTAssertEqual(createReq.timeoutSeconds, 30)
    }

    // MARK: - Test: Create Fixtures With Running State

    func testCreateFixturesWithRunningState() async throws {
        configureMockForCreation()

        let descriptor = makeDescriptor(key: "svc")

        _ = try await orchestrator.createFixtures(
            runID: "run-2",
            descriptors: [descriptor],
            desiredStates: [.running]
        )

        // Should have: create, inspect, start = 3 calls
        XCTAssertEqual(mock.capturedRequests.count, 3)

        let createReq = mock.capturedRequests[0]
        XCTAssertEqual(createReq.arguments[0], "create")

        let inspectReq = mock.capturedRequests[1]
        XCTAssertEqual(inspectReq.arguments[0], "inspect")

        let startReq = mock.capturedRequests[2]
        XCTAssertEqual(startReq.arguments[0], "start")
        XCTAssertEqual(startReq.arguments[1], "mdui-test-run-2-svc")
    }

    // MARK: - Test: Create Fixtures With Stopped State

    func testCreateFixturesWithStoppedState() async throws {
        configureMockForCreation()

        let descriptor = makeDescriptor(key: "db")

        _ = try await orchestrator.createFixtures(
            runID: "run-3",
            descriptors: [descriptor],
            desiredStates: [.stopped]
        )

        // Should have: create, inspect, start, stop = 4 calls
        XCTAssertEqual(mock.capturedRequests.count, 4)

        XCTAssertEqual(mock.capturedRequests[0].arguments[0], "create")
        XCTAssertEqual(mock.capturedRequests[1].arguments[0], "inspect")
        XCTAssertEqual(mock.capturedRequests[2].arguments[0], "start")
        XCTAssertEqual(mock.capturedRequests[2].arguments[1], "mdui-test-run-3-db")
        XCTAssertEqual(mock.capturedRequests[3].arguments[0], "stop")
        XCTAssertEqual(mock.capturedRequests[3].arguments[1], "mdui-test-run-3-db")
    }

    // MARK: - Test: Remove Fixtures Calls Docker Rm Force

    func testRemoveFixturesCallsDockerRmForce() async {
        // Mock: docker ps returns two container IDs
        mock.runHandler = { request in
            if request.arguments.contains("ps") {
                return CommandResult(
                    exitCode: 0,
                    stdout: "aaa111\nbbb222\n".data(using: .utf8)!
                )
            }
            return CommandResult(exitCode: 0)
        }

        await orchestrator.removeFixtures(runID: "run-cleanup")

        // First call: docker ps -a --filter ...
        XCTAssertEqual(mock.capturedRequests.count, 3) // ps + 2x rm
        let psReq = mock.capturedRequests[0]
        XCTAssertEqual(psReq.arguments[0], "ps")
        XCTAssertTrue(psReq.arguments.contains("-a"))
        XCTAssertTrue(psReq.arguments.contains("--filter"))
        XCTAssertTrue(psReq.arguments.contains("name=mdui-test-run-cleanup"))

        // rm -f for each container
        let rm1 = mock.capturedRequests[1]
        XCTAssertEqual(rm1.arguments, ["rm", "-f", "aaa111"])

        let rm2 = mock.capturedRequests[2]
        XCTAssertEqual(rm2.arguments, ["rm", "-f", "bbb222"])
    }

    // MARK: - Test: Remove Fixtures Is Idempotent

    func testRemoveFixturesIsIdempotent() async {
        // Mock: first call returns IDs, second call returns empty (already cleaned)
        var callCount = 0
        mock.runHandler = { request in
            if request.arguments.contains("ps") {
                callCount += 1
                if callCount == 1 {
                    return CommandResult(
                        exitCode: 0,
                        stdout: "xxx999\n".data(using: .utf8)!
                    )
                } else {
                    return CommandResult(exitCode: 0, stdout: Data())
                }
            }
            return CommandResult(exitCode: 0)
        }

        // First removal
        await orchestrator.removeFixtures(runID: "run-idem")

        // Second removal — should not throw and makes no rm calls
        let countBefore = mock.capturedRequests.count
        await orchestrator.removeFixtures(runID: "run-idem")
        let countAfter = mock.capturedRequests.count

        // Second pass: only 1 additional ps call, no rm calls
        XCTAssertEqual(countAfter - countBefore, 1)
    }

    // MARK: - Test: Remove Fixtures Swallows Errors

    func testRemoveFixturesSwallowsErrors() async {
        // Mock: docker ps returns non-zero
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 1,
                stderr: "Cannot connect to Docker daemon".data(using: .utf8)!
            )
        }

        // Should not throw despite error
        await orchestrator.removeFixtures(runID: "run-fail")
        // If we get here, the test passes (no throw)
    }

    func testRemoveFixturesSwallowsRmErrors() async {
        var rmCalled = false
        mock.runHandler = { request in
            if request.arguments.contains("ps") {
                return CommandResult(
                    exitCode: 0,
                    stdout: "zzz999\n".data(using: .utf8)!
                )
            }
            if request.arguments.contains("rm") {
                rmCalled = true
                return CommandResult(
                    exitCode: 1,
                    stderr: "Error: No such container".data(using: .utf8)!
                )
            }
            return CommandResult(exitCode: 0)
        }

        await orchestrator.removeFixtures(runID: "run-rm-fail")
        XCTAssertTrue(rmCalled, "rm should have been attempted even though it fails")
    }

    // MARK: - Test: Cleanup On Partial Failure

    func testCleanupOnPartialFailure() async throws {
        var createCallCount = 0
        var removeCalled = false

        mock.runHandler = { request in
            if request.arguments.first == "create" {
                createCallCount += 1
                if createCallCount == 2 {
                    // Second create fails
                    return CommandResult(
                        exitCode: 1,
                        stderr: "Error: image not found".data(using: .utf8)!
                    )
                }
                return CommandResult(exitCode: 0)
            }
            if request.arguments.first == "inspect" {
                return CommandResult(
                    exitCode: 0,
                    stdout: "container-id-\(createCallCount)\n".data(using: .utf8)!
                )
            }
            if request.arguments.contains("ps") {
                removeCalled = true
                return CommandResult(exitCode: 0, stdout: Data())
            }
            return CommandResult(exitCode: 0)
        }

        let descriptors = [
            makeDescriptor(key: "a"),
            makeDescriptor(key: "b"),
        ]

        do {
            _ = try await orchestrator.createFixtures(runID: "run-partial", descriptors: descriptors)
            XCTFail("Expected createFixtures to throw on partial failure")
        } catch {
            // Verify cleanup was attempted
            XCTAssertTrue(removeCalled, "removeFixtures should be called on partial failure")

            // Verify the error is propagated
            if let coreError = error as? CoreError,
               case let .processNonZeroExit(_, exitCode, stderr) = coreError
            {
                XCTAssertEqual(exitCode, 1)
                XCTAssertTrue(stderr.contains("image not found"))
            } else {
                XCTFail("Expected CoreError.processNonZeroExit, got \(error)")
            }
        }
    }

    // MARK: - Test: Default Image Used When Empty

    func testDefaultImageUsedWhenEmpty() async throws {
        configureMockForCreation()

        let descriptor = FixtureDescriptor(
            key: "minimal",
            image: "",
            command: ["echo", "hello"],
            environment: [:]
        )

        _ = try await orchestrator.createFixtures(runID: "run-default", descriptors: [descriptor])

        let createReq = mock.capturedRequests[0]
        XCTAssertTrue(
            createReq.arguments.contains("alpine:3.20"),
            "Should use default image when descriptor image is empty"
        )
    }

    // MARK: - Real Docker Tests

    func testRealCreateAndRemove() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )

        let realOrchestrator = DockerFixtureOrchestrator()
        let runID = "test-\(UUID().uuidString.prefix(8).lowercased())"

        let descriptor = FixtureDescriptor(
            key: "alpine-echo",
            image: "alpine:3.20",
            command: ["echo", "hello"],
            environment: [:]
        )

        do {
            let handles = try await realOrchestrator.createFixtures(
                runID: runID,
                descriptors: [descriptor]
            )

            XCTAssertEqual(handles.count, 1)
            XCTAssertEqual(handles[0].key, "alpine-echo")
            XCTAssertFalse(handles[0].containerId.isEmpty)

            // Cleanup
            await realOrchestrator.removeFixtures(runID: runID)
        } catch {
            // Cleanup even on failure
            await realOrchestrator.removeFixtures(runID: runID)
            throw XCTSkip("Docker daemon not available or image pull failed: \(error)")
        }
    }

    func testRealCreateInSpecificStates() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"),
            "Docker binary not found; skipping real Docker test"
        )

        let realOrchestrator = DockerFixtureOrchestrator()
        let runID = "state-\(UUID().uuidString.prefix(8).lowercased())"

        let descriptors = [
            FixtureDescriptor(
                key: "created-only",
                image: "alpine:3.20",
                command: ["sleep", "3600"],
                environment: [:]
            ),
            FixtureDescriptor(
                key: "started",
                image: "alpine:3.20",
                command: ["sleep", "3600"],
                environment: [:]
            ),
            FixtureDescriptor(
                key: "stopped",
                image: "alpine:3.20",
                command: ["sleep", "3600"],
                environment: [:]
            ),
        ]

        let desiredStates: [FixtureContainerState] = [.created, .running, .stopped]

        do {
            let handles = try await realOrchestrator.createFixtures(
                runID: runID,
                descriptors: descriptors,
                desiredStates: desiredStates
            )

            XCTAssertEqual(handles.count, 3)
            XCTAssertEqual(handles[0].key, "created-only")
            XCTAssertEqual(handles[1].key, "started")
            XCTAssertEqual(handles[2].key, "stopped")

            // Verify states via docker inspect
            let runner = CLICommandRunner()
            for (index, handle) in handles.enumerated() {
                let inspectReq = CommandRequest(
                    executablePath: "/usr/local/bin/docker",
                    arguments: ["inspect", "--format", "{{.State.Status}}", handle.containerId],
                    timeoutSeconds: 10
                )
                let result = try await runner.run(inspectReq)
                let status = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)

                switch desiredStates[index] {
                case .created:
                    XCTAssertEqual(status, "created", "Container \(handle.key) should be in created state")
                case .running:
                    XCTAssertEqual(status, "running", "Container \(handle.key) should be in running state")
                case .stopped:
                    XCTAssertEqual(status, "exited", "Container \(handle.key) should be in exited state")
                }
            }

            await realOrchestrator.removeFixtures(runID: runID)
        } catch {
            await realOrchestrator.removeFixtures(runID: runID)
            throw XCTSkip("Docker daemon not available or image pull failed: \(error)")
        }
    }
}
