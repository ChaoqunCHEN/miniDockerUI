@testable import MiniDockerCore
import XCTest

final class SchemaVersionTests: XCTestCase {
    // MARK: - Parsing

    func testParseValidVersion() throws {
        let version = try SchemaVersion(parsing: "1.2.3")
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
    }

    func testParseInvalidThrows() {
        XCTAssertThrowsError(try SchemaVersion(parsing: "not.a.version")) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected CoreError.outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testParseTooFewComponentsThrows() {
        XCTAssertThrowsError(try SchemaVersion(parsing: "1.2"))
    }

    func testParseTooManyComponentsThrows() {
        XCTAssertThrowsError(try SchemaVersion(parsing: "1.2.3.4"))
    }

    func testParseNegativeComponentThrows() {
        XCTAssertThrowsError(try SchemaVersion(parsing: "1.-2.3"))
    }

    // MARK: - Comparison

    func testComparison() {
        let v100 = SchemaVersion(major: 1, minor: 0, patch: 0)
        let v110 = SchemaVersion(major: 1, minor: 1, patch: 0)
        let v200 = SchemaVersion(major: 2, minor: 0, patch: 0)

        XCTAssertTrue(v100 < v110)
        XCTAssertTrue(v110 < v200)
        XCTAssertTrue(v100 < v200)
        XCTAssertFalse(v200 < v100)
    }

    func testPatchComparison() {
        let v100 = SchemaVersion(major: 1, minor: 0, patch: 0)
        let v101 = SchemaVersion(major: 1, minor: 0, patch: 1)
        XCTAssertTrue(v100 < v101)
    }

    // MARK: - Equality

    func testEquality() {
        let a = SchemaVersion(major: 1, minor: 0, patch: 0)
        let b = SchemaVersion(major: 1, minor: 0, patch: 0)
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = SchemaVersion(major: 1, minor: 0, patch: 0)
        let b = SchemaVersion(major: 1, minor: 0, patch: 1)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Description

    func testDescription() {
        let version = SchemaVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version.description, "1.2.3")
    }

    func testDescriptionZeros() {
        let version = SchemaVersion(major: 0, minor: 0, patch: 0)
        XCTAssertEqual(version.description, "0.0.0")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = SchemaVersion(major: 1, minor: 2, patch: 3)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SchemaVersion.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
