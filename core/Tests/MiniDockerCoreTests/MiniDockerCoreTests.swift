import XCTest
@testable import MiniDockerCore

final class MiniDockerCoreTests: XCTestCase {
    func testPreflightSummaryIsStable() {
        XCTAssertEqual(MiniDockerCore.preflightSummary(), "miniDockerUI core ready")
    }

    func testVersionIsSet() {
        XCTAssertFalse(MiniDockerCore.packageVersion.isEmpty)
    }
}
