import Foundation
@testable import MiniDockerCore
import XCTest

final class CLICommandRunnerTests: XCTestCase {
    private let runner = CLICommandRunner()

    // MARK: - run() tests

    func testRunEchoSuccess() async throws {
        let request = CommandRequest(
            executablePath: "/bin/echo",
            arguments: ["hello"]
        )
        let result = try await runner.run(request)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.stdoutString.contains("hello"))
    }

    func testRunNonZeroExit() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 42"]
        )
        let result = try await runner.run(request)

        XCTAssertEqual(result.exitCode, 42)
        XCTAssertFalse(result.isSuccess)
    }

    func testRunCheckedThrowsOnFailure() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 1"]
        )

        do {
            _ = try await runner.runChecked(request)
            XCTFail("Expected runChecked to throw for non-zero exit")
        } catch let error as CoreError {
            guard case let .processNonZeroExit(path, exitCode, _) = error else {
                XCTFail("Expected processNonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(path, "/bin/sh")
            XCTAssertEqual(exitCode, 1)
        }
    }

    func testRunCapturesStderr() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo err >&2"]
        )
        let result = try await runner.run(request)

        XCTAssertTrue(result.stderrString.contains("err"))
    }

    func testRunTimeout() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sleep",
            arguments: ["60"],
            timeoutSeconds: 0.5
        )

        do {
            _ = try await runner.run(request)
            XCTFail("Expected timeout error")
        } catch let error as CoreError {
            guard case let .processTimeout(path, timeout) = error else {
                XCTFail("Expected processTimeout, got \(error)")
                return
            }
            XCTAssertEqual(path, "/bin/sleep")
            XCTAssertEqual(timeout, 0.5)
        }
    }

    func testRunCancellation() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sleep",
            arguments: ["60"]
        )

        // Copy runner to a local to avoid capturing `self` across a sending boundary.
        let localRunner = runner
        let task = Task {
            try await localRunner.run(request)
        }

        // Give the process a moment to launch.
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch is CancellationError {
            // Acceptable
        } catch let error as CoreError {
            guard case .processCancelled = error else {
                XCTFail("Expected processCancelled, got \(error)")
                return
            }
        }
    }

    func testRunLaunchFailure() async throws {
        let request = CommandRequest(
            executablePath: "/nonexistent/binary"
        )

        do {
            _ = try await runner.run(request)
            XCTFail("Expected launch failure")
        } catch let error as CoreError {
            guard case let .processLaunchFailed(path, _) = error else {
                XCTFail("Expected processLaunchFailed, got \(error)")
                return
            }
            XCTAssertEqual(path, "/nonexistent/binary")
        }
    }

    func testRunWithEnvironment() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo $TEST_VAR"],
            environment: ["TEST_VAR": "hello"]
        )
        let result = try await runner.run(request)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdoutString.contains("hello"))
    }

    // MARK: - stream() tests

    func testStreamYieldsData() async throws {
        let request = CommandRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo line1; echo line2"]
        )

        var collectedData = Data()
        for try await chunk in runner.stream(request) {
            collectedData.append(chunk)
        }

        let output = String(data: collectedData, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("line1"))
        XCTAssertTrue(output.contains("line2"))
    }
}
