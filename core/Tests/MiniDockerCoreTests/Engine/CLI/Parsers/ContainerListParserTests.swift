import Foundation
@testable import MiniDockerCore
import XCTest

final class ContainerListParserTests: XCTestCase {
    private let parser = ContainerListParser()
    private let ctx = "test-ctx"

    // MARK: - Happy Path

    func testParseEmptyOutput() throws {
        let result = try parser.parseList(output: "", engineContextId: ctx)
        XCTAssertTrue(result.isEmpty)
    }

    func testParseSingleContainer() throws {
        let json = """
        {"ID":"abc123","Names":"my-app","Image":"nginx:latest","Status":"Up 2 hours","Labels":"","State":"running","CreatedAt":"2026-02-22 10:00:00 +0000 UTC"}
        """
        let result = try parser.parseList(output: json, engineContextId: ctx)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "abc123")
        XCTAssertEqual(result[0].name, "my-app")
        XCTAssertEqual(result[0].image, "nginx:latest")
        XCTAssertEqual(result[0].status, "Up 2 hours")
        XCTAssertEqual(result[0].engineContextId, ctx)
    }

    func testParseMultipleContainers() throws {
        let json = """
        {"ID":"aaa","Names":"web","Image":"nginx","Status":"Up 1 hour","Labels":"","CreatedAt":""}
        {"ID":"bbb","Names":"db","Image":"postgres","Status":"Up 2 hours","Labels":"","CreatedAt":""}
        {"ID":"ccc","Names":"cache","Image":"redis","Status":"Exited (0)","Labels":"","CreatedAt":""}
        """
        let result = try parser.parseList(output: json, engineContextId: ctx)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].id, "aaa")
        XCTAssertEqual(result[1].id, "bbb")
        XCTAssertEqual(result[2].id, "ccc")
    }

    func testParseHealthyStatus() throws {
        let json = """
        {"ID":"h1","Names":"web","Image":"nginx","Status":"Up 2 hours (healthy)","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.health, .healthy)
    }

    func testParseUnhealthyStatus() throws {
        let json = """
        {"ID":"h2","Names":"web","Image":"nginx","Status":"Up 2 hours (unhealthy)","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.health, .unhealthy)
    }

    func testParseStartingStatus() throws {
        let json = """
        {"ID":"h3","Names":"web","Image":"nginx","Status":"Up 5 seconds (health: starting)","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.health, .starting)
    }

    func testParseNoHealthCheck() throws {
        let json = """
        {"ID":"h4","Names":"web","Image":"nginx","Status":"Up 2 hours","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertNil(result.health)
    }

    // MARK: - Edge Cases

    func testParseLabelsWithEqualsInValue() throws {
        let json = """
        {"ID":"l1","Names":"web","Image":"nginx","Status":"Up","Labels":"env=prod=us-east,tier=frontend"}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.labels["env"], "prod=us-east")
        XCTAssertEqual(result.labels["tier"], "frontend")
    }

    func testParseEmptyLabels() throws {
        let json = """
        {"ID":"l2","Names":"web","Image":"nginx","Status":"Up","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertTrue(result.labels.isEmpty)
    }

    func testParseBlankLinesSkipped() throws {
        let json = """
        {"ID":"a","Names":"web","Image":"nginx","Status":"Up","Labels":""}

        {"ID":"b","Names":"db","Image":"postgres","Status":"Up","Labels":""}

        """
        let result = try parser.parseList(output: json, engineContextId: ctx)
        XCTAssertEqual(result.count, 2)
    }

    func testParseExtraFieldsIgnored() throws {
        let json = """
        {"ID":"x1","Names":"web","Image":"nginx","Status":"Up","Labels":"","Size":"100MB","Ports":"0.0.0.0:80->80/tcp","Networks":"bridge"}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.id, "x1")
    }

    func testParseContainerNameStripSlash() throws {
        let json = """
        {"ID":"s1","Names":"/my-container","Image":"nginx","Status":"Up","Labels":""}
        """
        let result = try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)
        XCTAssertEqual(result.name, "my-container")
    }

    // MARK: - Error Cases

    func testParseMalformedJSON() throws {
        XCTAssertThrowsError(try parser.parseSingleContainer(jsonLine: "{broken json", engineContextId: ctx)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseMissingIdField() throws {
        let json = """
        {"Names":"web","Image":"nginx","Status":"Up","Labels":""}
        """
        XCTAssertThrowsError(try parser.parseSingleContainer(jsonLine: json, engineContextId: ctx)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }
}
