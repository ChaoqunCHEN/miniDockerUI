@testable import MiniDockerCore
import XCTest

final class CoreErrorLocalizedTests: XCTestCase {
    func testAllCasesHaveNonEmptyDescription() {
        let allCases: [CoreError] = [
            .dependencyNotFound(name: "docker", searchedPaths: ["/usr/local/bin"]),
            .dependencyVersionUnsupported(name: "docker", found: "19.03", required: "20.10"),
            .endpointUnreachable(
                endpoint: EngineEndpoint(endpointType: .local, address: "/var/run/docker.sock"),
                reason: "connection refused"
            ),
            .contextNotConfigured(contextId: "remote"),
            .processLaunchFailed(executablePath: "/usr/bin/docker", reason: "not found"),
            .processNonZeroExit(executablePath: "/usr/bin/docker", exitCode: 1, stderr: "error"),
            .processTimeout(executablePath: "/usr/bin/docker", timeoutSeconds: 30),
            .processCancelled(executablePath: "/usr/bin/docker"),
            .outputParseFailure(context: "test", rawSnippet: "bad data"),
            .contractViolation(expected: "array", actual: "string"),
            .fileReadFailed(path: "/tmp/test", reason: "permission denied"),
            .fileWriteFailed(path: "/tmp/test", reason: "disk full"),
            .directoryCreateFailed(path: "/tmp/test", reason: "permission denied"),
            .decodingFailed(context: "settings", reason: "invalid JSON"),
            .encodingFailed(context: "settings", reason: "invalid data"),
            .operationNotPermitted(action: "delete", reason: "read-only"),
            .schemaMigrationUnsupported(from: "0.9.0", to: "2.0.0"),
            .schemaDowngradeRejected(current: "1.1.0", requested: "1.0.0"),
            .keychainOperationFailed(operation: "read", osStatus: -25300),
        ]

        for error in allCases {
            let description = error.errorDescription
            XCTAssertNotNil(description, "Missing errorDescription for \(error)")
            XCTAssertFalse(description?.isEmpty ?? true, "Empty errorDescription for \(error)")
        }
    }

    func testLocalizedDescriptionUsesErrorDescription() {
        let error = CoreError.fileReadFailed(path: "/tmp/test.json", reason: "no such file")
        XCTAssertTrue(error.localizedDescription.contains("/tmp/test.json"))
        XCTAssertTrue(error.localizedDescription.contains("no such file"))
    }
}
