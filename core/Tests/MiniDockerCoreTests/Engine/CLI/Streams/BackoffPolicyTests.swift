import Foundation
@testable import MiniDockerCore
import XCTest

final class BackoffPolicyTests: XCTestCase {
    func testDefaultPolicyValues() {
        let policy = BackoffPolicy()
        XCTAssertEqual(policy.initialDelay, .seconds(1))
        XCTAssertEqual(policy.maxDelay, .seconds(30))
        XCTAssertEqual(policy.maxRetries, 10)
        XCTAssertEqual(policy.multiplier, 2.0)
    }

    func testDelayForAttemptZeroReturnsInitialDelay() {
        let policy = BackoffPolicy(initialDelay: .seconds(2))
        let delay = policy.delay(forAttempt: 0)
        XCTAssertEqual(delay, .seconds(2))
    }

    func testDelayGrowsExponentially() {
        let policy = BackoffPolicy(
            initialDelay: .seconds(1),
            maxDelay: .seconds(120),
            multiplier: 2.0
        )
        XCTAssertEqual(policy.delay(forAttempt: 0), .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 1), .seconds(2))
        XCTAssertEqual(policy.delay(forAttempt: 2), .seconds(4))
        XCTAssertEqual(policy.delay(forAttempt: 3), .seconds(8))
    }

    func testDelayCapsAtMaxDelay() {
        let policy = BackoffPolicy(
            initialDelay: .seconds(1),
            maxDelay: .seconds(10),
            multiplier: 2.0
        )
        // Attempt 4 would be 16s, but capped at 10s
        XCTAssertEqual(policy.delay(forAttempt: 4), .seconds(10))
        XCTAssertEqual(policy.delay(forAttempt: 100), .seconds(10))
    }

    func testCustomMultiplier() {
        let policy = BackoffPolicy(
            initialDelay: .seconds(1),
            maxDelay: .seconds(1000),
            multiplier: 3.0
        )
        XCTAssertEqual(policy.delay(forAttempt: 0), .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 1), .seconds(3))
        XCTAssertEqual(policy.delay(forAttempt: 2), .seconds(9))
        XCTAssertEqual(policy.delay(forAttempt: 3), .seconds(27))
    }

    func testNegativeAttemptReturnsInitialDelay() {
        let policy = BackoffPolicy(initialDelay: .seconds(5))
        XCTAssertEqual(policy.delay(forAttempt: -1), .seconds(5))
    }

    func testEquatableConformance() {
        let a = BackoffPolicy(initialDelay: .seconds(1), maxDelay: .seconds(30), maxRetries: 10, multiplier: 2.0)
        let b = BackoffPolicy(initialDelay: .seconds(1), maxDelay: .seconds(30), maxRetries: 10, multiplier: 2.0)
        let c = BackoffPolicy(initialDelay: .seconds(2), maxDelay: .seconds(30), maxRetries: 10, multiplier: 2.0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
