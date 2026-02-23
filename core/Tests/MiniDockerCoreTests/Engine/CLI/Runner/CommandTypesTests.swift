import Foundation
@testable import MiniDockerCore
import XCTest

final class CommandTypesTests: XCTestCase {
    // MARK: - CommandRequest Codable

    func testCommandRequestCodableRoundTrip() throws {
        let request = CommandRequest(
            executablePath: "/usr/local/bin/docker",
            arguments: ["ps", "--format", "json"],
            environment: ["DOCKER_HOST": "unix:///var/run/docker.sock"],
            workingDirectory: "/tmp",
            timeoutSeconds: 30.0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(CommandRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    // MARK: - CommandResult isSuccess

    func testCommandResultIsSuccess() {
        let success = CommandResult(exitCode: 0)
        XCTAssertTrue(success.isSuccess)

        let failure = CommandResult(exitCode: 42)
        XCTAssertFalse(failure.isSuccess)
    }

    // MARK: - CommandResult string conversion

    func testCommandResultStringConversion() {
        let stdoutBytes = Data("hello stdout".utf8)
        let stderrBytes = Data("hello stderr".utf8)

        let result = CommandResult(
            exitCode: 0,
            stdout: stdoutBytes,
            stderr: stderrBytes,
            durationSeconds: 1.5
        )

        XCTAssertEqual(result.stdoutString, "hello stdout")
        XCTAssertEqual(result.stderrString, "hello stderr")
    }
}
