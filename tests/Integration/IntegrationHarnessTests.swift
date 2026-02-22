import Foundation
import XCTest
@testable import MiniDockerCore

final class IntegrationHarnessTests: XCTestCase {
    func testRunIDPrefixShape() {
        let runID = "run-\(UUID().uuidString.lowercased())"
        XCTAssertTrue(runID.hasPrefix("run-"))
    }

    func testCoreIsReachableFromIntegrationHarness() {
        XCTAssertEqual(MiniDockerCore.preflightSummary(), "miniDockerUI core ready")
    }
}
