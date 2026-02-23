import Foundation
@testable import MiniDockerCore
import XCTest

final class ContainerInspectParserTests: XCTestCase {
    private let parser = ContainerInspectParser()
    private let ctx = "test-ctx"

    // MARK: - Happy Path

    func testParseFullInspect() throws {
        let json = makeInspectJSON()
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        XCTAssertEqual(detail.summary.id, "abc123def456")
        XCTAssertEqual(detail.summary.name, "my-container")
        XCTAssertEqual(detail.summary.image, "nginx:latest")
        XCTAssertEqual(detail.summary.status, "running")
    }

    func testParseMountsMapping() throws {
        let json = makeInspectJSON()
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        XCTAssertEqual(detail.mounts.count, 1)
        XCTAssertEqual(detail.mounts[0].source, "/host/data")
        XCTAssertEqual(detail.mounts[0].destination, "/container/data")
        XCTAssertEqual(detail.mounts[0].isReadOnly, false)
    }

    func testParseNetworkSettings() throws {
        let json = makeInspectJSON()
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        XCTAssertEqual(detail.networkSettings.networkMode, "bridge")
        XCTAssertEqual(detail.networkSettings.ipAddressesByNetwork["bridge"], "172.17.0.2")
        XCTAssertFalse(detail.networkSettings.ports.isEmpty)
    }

    func testParseHealthDetail() throws {
        let json = makeInspectJSON(includeHealth: true)
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        XCTAssertNotNil(detail.healthDetail)
        XCTAssertEqual(detail.healthDetail?.status, .healthy)
        XCTAssertEqual(detail.healthDetail?.failingStreak, 0)
    }

    func testParseNoHealthConfig() throws {
        let json = makeInspectJSON(includeHealth: false)
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        XCTAssertNil(detail.healthDetail)
    }

    func testParseRawInspectPreserved() throws {
        let json = makeInspectJSON()
        let detail = try parser.parseInspect(output: json, engineContextId: ctx)
        // rawInspect should be a non-null JSONValue
        if case .null = detail.rawInspect {
            XCTFail("Expected rawInspect to be non-null")
        }
    }

    // MARK: - Error Cases

    func testParseEmptyArray() throws {
        XCTAssertThrowsError(try parser.parseInspect(output: "[]", engineContextId: ctx)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseMalformedJSON() throws {
        XCTAssertThrowsError(try parser.parseInspect(output: "not json", engineContextId: ctx)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseMissingIdField() throws {
        let json = """
        [{"Name":"/test","Config":{"Image":"nginx"},"State":{"Status":"running"}}]
        """
        XCTAssertThrowsError(try parser.parseInspect(output: json, engineContextId: ctx)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func makeInspectJSON(includeHealth: Bool = true) -> String {
        let healthBlock: String
        if includeHealth {
            healthBlock = """
            ,"Health":{"Status":"healthy","FailingStreak":0,"Log":[{"Start":"2026-02-22T10:00:00.000000000Z","End":"2026-02-22T10:00:01.000000000Z","ExitCode":0,"Output":"ok"}]}
            """
        } else {
            healthBlock = ""
        }

        return """
        [{"Id":"abc123def456","Name":"/my-container","Config":{"Image":"nginx:latest","Labels":{"env":"prod"}},"State":{"Status":"running","StartedAt":"2026-02-22T10:00:00.000000000Z"\(healthBlock)},"Mounts":[{"Source":"/host/data","Destination":"/container/data","Mode":"rw","RW":true}],"NetworkSettings":{"Ports":{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"8080"}]},"Networks":{"bridge":{"IPAddress":"172.17.0.2"}}},"HostConfig":{"NetworkMode":"bridge"}}]
        """
    }
}
