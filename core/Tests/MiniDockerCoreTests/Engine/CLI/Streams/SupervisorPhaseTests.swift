import Foundation
@testable import MiniDockerCore
import XCTest

final class SupervisorPhaseTests: XCTestCase {
    func testAllCasesConstructible() {
        let now = Date()
        let phases: [SupervisorPhase] = [
            .idle,
            .connecting,
            .streaming,
            .disconnected(at: now, attempt: 1),
            .backingOff(until: now, attempt: 2),
            .resyncing,
            .exhausted(totalAttempts: 10),
            .stopped,
        ]
        XCTAssertEqual(phases.count, 8)
    }

    func testEquatableConformance() {
        let now = Date()
        XCTAssertEqual(SupervisorPhase.idle, SupervisorPhase.idle)
        XCTAssertEqual(SupervisorPhase.streaming, SupervisorPhase.streaming)
        XCTAssertEqual(
            SupervisorPhase.disconnected(at: now, attempt: 1),
            SupervisorPhase.disconnected(at: now, attempt: 1)
        )
        XCTAssertNotEqual(SupervisorPhase.idle, SupervisorPhase.streaming)
        XCTAssertNotEqual(
            SupervisorPhase.disconnected(at: now, attempt: 1),
            SupervisorPhase.disconnected(at: now, attempt: 2)
        )
    }

    func testExhaustedCarriesTotalAttempts() {
        let phase = SupervisorPhase.exhausted(totalAttempts: 5)
        if case let .exhausted(total) = phase {
            XCTAssertEqual(total, 5)
        } else {
            XCTFail("Expected .exhausted case")
        }
    }
}
