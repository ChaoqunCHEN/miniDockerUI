import Foundation
@testable import MiniDockerCore
import XCTest

final class EventStreamParserTests: XCTestCase {
    private let parser = EventStreamParser()

    func testParseContainerStartEvent() throws {
        let json = """
        {"status":"start","id":"abc123","Type":"container","Action":"start","Actor":{"ID":"abc123","Attributes":{"name":"web"}},"time":1708600000,"timeNano":1708600000000000000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 1)
        XCTAssertEqual(envelope.action, "start")
        XCTAssertEqual(envelope.containerId, "abc123")
        XCTAssertEqual(envelope.source, "container")
        XCTAssertEqual(envelope.sequence, 1)
    }

    func testParseContainerDieEvent() throws {
        let json = """
        {"status":"die","id":"abc123","Type":"container","Action":"die","Actor":{"ID":"abc123","Attributes":{"exitCode":"1","name":"web"}},"time":1708600100,"timeNano":1708600100000000000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 2)
        XCTAssertEqual(envelope.action, "die")
        XCTAssertEqual(envelope.attributes["exitCode"], "1")
    }

    func testParseNonContainerEvent() throws {
        let json = """
        {"Type":"network","Action":"create","Actor":{"ID":"net123","Attributes":{"name":"bridge"}},"time":1708600200,"timeNano":1708600200000000000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 3)
        XCTAssertEqual(envelope.source, "network")
        XCTAssertEqual(envelope.action, "create")
        // Actor.ID is "net123" — it's a network event, not container
        XCTAssertEqual(envelope.containerId, "net123")
    }

    func testParseTimeNanoPrecision() throws {
        let json = """
        {"Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{}},"time":1708600000,"timeNano":1708600000123456789}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 4)
        let expected = Date(timeIntervalSince1970: 1_708_600_000.123456789)
        XCTAssertEqual(envelope.eventAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testParseFallbackToTimeField() throws {
        let json = """
        {"Type":"container","Action":"stop","Actor":{"ID":"abc","Attributes":{}},"time":1708600000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 5)
        XCTAssertEqual(envelope.eventAt.timeIntervalSince1970, 1_708_600_000, accuracy: 1)
    }

    func testParseAttributes() throws {
        let json = """
        {"Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{"name":"web","image":"nginx:latest"}},"time":1708600000,"timeNano":1708600000000000000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 6)
        XCTAssertEqual(envelope.attributes["name"], "web")
        XCTAssertEqual(envelope.attributes["image"], "nginx:latest")
    }

    func testParseMalformedLine() throws {
        XCTAssertThrowsError(try parser.parseEventLine(line: "not json", sequenceNumber: 7)) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseRawPreserved() throws {
        let json = """
        {"Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{}},"time":1708600000,"timeNano":1708600000000000000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 8)
        XCTAssertNotNil(envelope.raw)
    }

    func testSequenceNumberPassthrough() throws {
        let json = """
        {"Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{}},"time":1708600000}
        """
        let envelope = try parser.parseEventLine(line: json, sequenceNumber: 42)
        XCTAssertEqual(envelope.sequence, 42)
    }
}
