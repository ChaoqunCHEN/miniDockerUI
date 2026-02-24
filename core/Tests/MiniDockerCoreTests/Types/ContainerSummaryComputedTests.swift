import Foundation
@testable import MiniDockerCore
import XCTest

final class ContainerSummaryComputedTests: XCTestCase {
    // MARK: - isRunning

    func testIsRunningForUpStatus() {
        XCTAssertTrue(makeSummary(status: "Up 5 minutes").isRunning)
        XCTAssertTrue(makeSummary(status: "Up 2 hours").isRunning)
        XCTAssertTrue(makeSummary(status: "up About an hour").isRunning)
    }

    func testIsRunningForNonUpStatus() {
        XCTAssertFalse(makeSummary(status: "Exited (0) 1 minute ago").isRunning)
        XCTAssertFalse(makeSummary(status: "Created").isRunning)
        XCTAssertFalse(makeSummary(status: "Paused").isRunning)
    }

    // MARK: - displayStatus

    func testDisplayStatusRunning() {
        XCTAssertEqual(makeSummary(status: "Up 5 minutes").displayStatus, "Running")
    }

    func testDisplayStatusExited() {
        XCTAssertEqual(makeSummary(status: "Exited (0) 1 minute ago").displayStatus, "Exited")
    }

    func testDisplayStatusCreated() {
        XCTAssertEqual(makeSummary(status: "Created").displayStatus, "Created")
    }

    func testDisplayStatusPaused() {
        XCTAssertEqual(makeSummary(status: "Paused").displayStatus, "Paused")
    }

    func testDisplayStatusUnknownFallsBackToRaw() {
        XCTAssertEqual(makeSummary(status: "Restarting (1) 5 seconds ago").displayStatus, "Restarting (1) 5 seconds ago")
    }

    // MARK: - statusColor

    func testStatusColorRunningHealthy() {
        XCTAssertEqual(makeSummary(status: "Up 5 minutes", health: .healthy).statusColor, .running)
    }

    func testStatusColorRunningNoHealth() {
        XCTAssertEqual(makeSummary(status: "Up 5 minutes", health: nil).statusColor, .running)
    }

    func testStatusColorRunningUnhealthy() {
        XCTAssertEqual(makeSummary(status: "Up 5 minutes", health: .unhealthy).statusColor, .warning)
    }

    func testStatusColorStopped() {
        XCTAssertEqual(makeSummary(status: "Exited (0) 1 minute ago").statusColor, .stopped)
    }

    func testStatusColorRunningStartingHealth() {
        XCTAssertEqual(makeSummary(status: "Up 5 minutes", health: .starting).statusColor, .running)
    }

    // MARK: - Helpers

    private func makeSummary(
        status: String,
        health: ContainerHealthStatus? = nil
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local",
            id: "test-id",
            name: "test-container",
            image: "test:latest",
            status: status,
            health: health,
            labels: [:],
            startedAt: nil
        )
    }
}
