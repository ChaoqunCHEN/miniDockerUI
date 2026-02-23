import Foundation
@testable import MiniDockerCore
import XCTest

final class IntegrationHarnessTests: XCTestCase {
    func testRunIDPrefixShape() {
        let runID = "run-\(UUID().uuidString.lowercased())"
        XCTAssertTrue(runID.hasPrefix("run-"))
    }

    func testCoreIsReachableFromIntegrationHarness() {
        XCTAssertEqual(MiniDockerCore.preflightSummary(), "miniDockerUI core ready")
    }
}
