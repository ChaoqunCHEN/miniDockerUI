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

final class CLIComposeAdapterTests: XCTestCase {
    private var mock: MockCommandRunner!
    private var adapter: CLIComposeAdapter!

    override func setUp() {
        mock = MockCommandRunner()
        adapter = CLIComposeAdapter(
            dockerPath: "/usr/local/bin/docker",
            runner: mock
        )
    }

    // MARK: - recreateService

    func testRecreateServiceBuildsCorrectArguments() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        try await adapter.recreateService(
            projectName: "myproject",
            projectDirectory: "/home/user/myproject",
            configFiles: [],
            serviceName: "web",
            timeoutSeconds: nil
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        XCTAssertEqual(req.executablePath, "/usr/local/bin/docker")
        XCTAssertEqual(req.arguments, [
            "compose", "-p", "myproject",
            "--project-directory", "/home/user/myproject",
            "up", "-d", "--force-recreate", "--no-deps", "web",
        ])
    }

    func testRecreateServiceWithConfigFiles() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        try await adapter.recreateService(
            projectName: "myproject",
            projectDirectory: "/home/user/myproject",
            configFiles: ["docker-compose.yml", "docker-compose.override.yml"],
            serviceName: "api",
            timeoutSeconds: nil
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        XCTAssertEqual(req.arguments, [
            "compose", "-p", "myproject",
            "--project-directory", "/home/user/myproject",
            "-f", "docker-compose.yml",
            "-f", "docker-compose.override.yml",
            "up", "-d", "--force-recreate", "--no-deps", "api",
        ])
    }

    func testRecreateServiceWithEmptyConfigFiles() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        try await adapter.recreateService(
            projectName: "proj",
            projectDirectory: "/tmp/proj",
            configFiles: [],
            serviceName: "db",
            timeoutSeconds: nil
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        // No -f flags should be present
        XCTAssertFalse(req.arguments.contains("-f"))
        XCTAssertEqual(req.arguments, [
            "compose", "-p", "proj",
            "--project-directory", "/tmp/proj",
            "up", "-d", "--force-recreate", "--no-deps", "db",
        ])
    }

    func testRecreateServiceThrowsOnFailure() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 1,
                stderr: "service not found".data(using: .utf8)!
            )
        }
        do {
            try await adapter.recreateService(
                projectName: "myproject",
                projectDirectory: "/home/user/myproject",
                configFiles: [],
                serviceName: "web",
                timeoutSeconds: nil
            )
            XCTFail("Expected error")
        } catch let error as CoreError {
            if case let .composeRecreationFailed(projectName, service, stderr) = error {
                XCTAssertEqual(projectName, "myproject")
                XCTAssertEqual(service, "web")
                XCTAssertEqual(stderr, "service not found")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRecreateServiceUsesDefaultTimeout() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        try await adapter.recreateService(
            projectName: "proj",
            projectDirectory: "/tmp",
            configFiles: [],
            serviceName: "svc",
            timeoutSeconds: nil
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        XCTAssertEqual(req.timeoutSeconds, 120)
    }

    func testRecreateServiceUsesCustomTimeout() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        try await adapter.recreateService(
            projectName: "proj",
            projectDirectory: "/tmp",
            configFiles: [],
            serviceName: "svc",
            timeoutSeconds: 60
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        XCTAssertEqual(req.timeoutSeconds, 60)
    }

    // MARK: - validateConfigExists

    func testValidateConfigBuildsCorrectArguments() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        _ = try await adapter.validateConfigExists(
            projectDirectory: "/home/user/myproject",
            configFiles: ["compose.yaml"]
        )
        let req = try XCTUnwrap(mock.capturedRunRequests.first)
        XCTAssertEqual(req.executablePath, "/usr/local/bin/docker")
        XCTAssertEqual(req.arguments, [
            "compose",
            "--project-directory", "/home/user/myproject",
            "-f", "compose.yaml",
            "config", "--quiet",
        ])
    }

    func testValidateConfigReturnsTrueOnSuccess() async throws {
        mock.runHandler = { _ in CommandResult(exitCode: 0) }
        let result = try await adapter.validateConfigExists(
            projectDirectory: "/home/user/myproject",
            configFiles: []
        )
        XCTAssertTrue(result)
    }

    func testValidateConfigReturnsFalseOnFailure() async throws {
        mock.runHandler = { _ in
            CommandResult(
                exitCode: 1,
                stderr: "no configuration file provided".data(using: .utf8)!
            )
        }
        let result = try await adapter.validateConfigExists(
            projectDirectory: "/nonexistent",
            configFiles: []
        )
        XCTAssertFalse(result)
    }
}
