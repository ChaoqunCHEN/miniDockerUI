@testable import MiniDockerCore
import XCTest

final class MiniDockerCoreTests: XCTestCase {
    func testPreflightSummaryIsStable() {
        XCTAssertEqual(MiniDockerCore.preflightSummary(), "miniDockerUI core ready")
    }

    func testVersionIsSet() {
        XCTAssertFalse(MiniDockerCore.packageVersion.isEmpty)
    }
}
