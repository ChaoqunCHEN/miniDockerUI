@testable import MiniDockerCore
import XCTest

final class DataLineAccumulatorTests: XCTestCase {
    func testSingleCompleteLine() throws {
        var acc = DataLineAccumulator()
        let lines = try acc.feed(XCTUnwrap("hello\n".data(using: .utf8)))
        XCTAssertEqual(lines, ["hello"])
    }

    func testMultipleLines() throws {
        var acc = DataLineAccumulator()
        let lines = try acc.feed(XCTUnwrap("line1\nline2\nline3\n".data(using: .utf8)))
        XCTAssertEqual(lines, ["line1", "line2", "line3"])
    }

    func testPartialLineCarryOver() throws {
        var acc = DataLineAccumulator()
        let first = try acc.feed(XCTUnwrap("hel".data(using: .utf8)))
        XCTAssertEqual(first, [])

        let second = try acc.feed(XCTUnwrap("lo\n".data(using: .utf8)))
        XCTAssertEqual(second, ["hello"])
    }

    func testPartialLineAcrossMultipleChunks() throws {
        var acc = DataLineAccumulator()
        _ = try acc.feed(XCTUnwrap("part".data(using: .utf8)))
        _ = try acc.feed(XCTUnwrap("ial".data(using: .utf8)))
        let lines = try acc.feed(XCTUnwrap(" line\n".data(using: .utf8)))
        XCTAssertEqual(lines, ["partial line"])
    }

    func testMixedCompleteAndPartial() throws {
        var acc = DataLineAccumulator()
        let lines = try acc.feed(XCTUnwrap("complete\npart".data(using: .utf8)))
        XCTAssertEqual(lines, ["complete"])

        let more = try acc.feed(XCTUnwrap("ial\n".data(using: .utf8)))
        XCTAssertEqual(more, ["partial"])
    }

    func testEmptyData() {
        var acc = DataLineAccumulator()
        let lines = acc.feed(Data())
        XCTAssertEqual(lines, [])
    }

    func testFlushReturnsPartialLine() throws {
        var acc = DataLineAccumulator()
        _ = try acc.feed(XCTUnwrap("no newline".data(using: .utf8)))
        let remaining = acc.flush()
        XCTAssertEqual(remaining, "no newline")
    }

    func testFlushReturnsNilWhenEmpty() {
        var acc = DataLineAccumulator()
        XCTAssertNil(acc.flush())
    }

    func testFlushAfterCompleteLine() throws {
        var acc = DataLineAccumulator()
        _ = try acc.feed(XCTUnwrap("complete\n".data(using: .utf8)))
        XCTAssertNil(acc.flush())
    }

    func testEmptyLines() throws {
        var acc = DataLineAccumulator()
        let lines = try acc.feed(XCTUnwrap("\n\n\n".data(using: .utf8)))
        XCTAssertEqual(lines, ["", "", ""])
    }
}
