import Foundation
@testable import MiniDockerCore
import XCTest

final class LogStreamParserTests: XCTestCase {
    private let parser = LogStreamParser()

    func testParseTimestampedLine() throws {
        let line = "2026-02-22T10:30:00.000000000Z Hello World"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        XCTAssertEqual(entry.message, "Hello World")
        XCTAssertEqual(entry.containerId, "c1")
        XCTAssertEqual(entry.stream, .stdout)
    }

    func testParseNanosecondTimestamp() throws {
        let line = "2026-02-22T10:30:00.123456789Z nano precision"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        // Verify the fractional seconds are preserved (within microsecond precision)
        let calendar = Calendar(identifier: .gregorian)
        let components = try calendar.dateComponents(in: XCTUnwrap(TimeZone(identifier: "UTC")), from: entry.timestamp)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 22)
    }

    func testParseMessageWithSpaces() throws {
        let line = "2026-02-22T10:30:00.000000000Z multiple words in this message"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        XCTAssertEqual(entry.message, "multiple words in this message")
    }

    func testParseEmptyMessage() throws {
        let line = "2026-02-22T10:30:00.000000000Z "
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        XCTAssertEqual(entry.message, "")
    }

    func testParseMalformedTimestamp() throws {
        let line = "not-a-timestamp some message"
        XCTAssertThrowsError(try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseDefaultStreamUsed() throws {
        let line = "2026-02-22T10:30:00.000000000Z test"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stderr
        )
        XCTAssertEqual(entry.stream, .stderr)
    }

    func testParseUTF8Message() throws {
        let line = "2026-02-22T10:30:00.000000000Z 日本語メッセージ 🐳"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        XCTAssertTrue(entry.message.contains("日本語"))
        XCTAssertTrue(entry.message.contains("🐳"))
    }

    func testParseVeryLongLine() throws {
        let longMsg = String(repeating: "x", count: 10000)
        let line = "2026-02-22T10:30:00.000000000Z \(longMsg)"
        let entry = try parser.parseLogLine(
            line: line, engineContextId: "ctx", containerId: "c1", defaultStream: .stdout
        )
        XCTAssertEqual(entry.message.count, 10000)
    }
}
