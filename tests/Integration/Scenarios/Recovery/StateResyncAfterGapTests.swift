import Foundation
@testable import MiniDockerCore
import XCTest

// MARK: - State Resync After Gap Tests

/// Tests for ContainerStateReducer sequence gap detection, resync resolution,
/// batch apply stopping at gaps, and ContainerStateHolder thread safety.
final class StateResyncAfterGapTests: XCTestCase {
    // MARK: - Helpers

    private func makeInitialState(containers: [ContainerSummary] = []) -> ContainerState {
        ContainerStateReducer.applySnapshot(
            containers,
            to: .empty,
            at: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func makeEvent(
        sequence: UInt64,
        containerId: String = "c1",
        action: String = "start"
    ) -> EventEnvelope {
        EventEnvelopeFactory.make(
            sequence: sequence,
            containerId: containerId,
            action: action
        )
    }

    // MARK: - Sequence Gap Detection

    func testSequenceGapTriggersResyncRequired() {
        let container = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        var state = makeInitialState(containers: [container])

        // Apply events 0, 1, 2 normally
        for seq in UInt64(0) ... 2 {
            let (newState, action) = ContainerStateReducer.applyEvent(
                makeEvent(sequence: seq),
                to: state
            )
            state = newState
            XCTAssertEqual(action, .none, "Event \(seq) should be accepted")
        }

        XCTAssertEqual(state.lastEventSequence, 2)

        // Apply event 5 (gap: expected 3)
        let (gapState, gapAction) = ContainerStateReducer.applyEvent(
            makeEvent(sequence: 5),
            to: state
        )

        if case let .resyncRequired(reason) = gapAction {
            XCTAssertTrue(reason.contains("gap"), "Reason should mention gap: \(reason)")
        } else {
            XCTFail("Expected resyncRequired action, got \(gapAction)")
        }

        if case let .resyncRequired(reason) = gapState.syncStatus {
            XCTAssertTrue(reason.contains("gap"))
        } else {
            XCTFail("Expected resyncRequired sync status")
        }

        // lastEventSequence should NOT advance past the gap
        XCTAssertEqual(gapState.lastEventSequence, 2)
    }

    func testResyncSnapshotResolvesGap() {
        let container = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        var state = makeInitialState(containers: [container])

        // Apply events 0, 1, 2
        for seq in UInt64(0) ... 2 {
            let (newState, _) = ContainerStateReducer.applyEvent(
                makeEvent(sequence: seq),
                to: state
            )
            state = newState
        }

        // Trigger gap with event 5
        let (gapState, _) = ContainerStateReducer.applyEvent(
            makeEvent(sequence: 5),
            to: state
        )

        // Verify we are in resyncRequired
        if case .resyncRequired = gapState.syncStatus {
            // Expected
        } else {
            XCTFail("Expected resyncRequired status")
        }

        // Apply resync snapshot to resolve the gap
        let resyncContainer = ContainerSummaryFactory.make(
            id: "c1",
            name: "app",
            status: "Exited"
        )
        let resyncTime = Date(timeIntervalSince1970: 1_001_000)
        let resolvedState = ContainerStateReducer.applyResyncSnapshot(
            [resyncContainer],
            to: gapState,
            at: resyncTime
        )

        // Should be synced again
        if case let .synced(since) = resolvedState.syncStatus {
            XCTAssertEqual(since, resyncTime)
        } else {
            XCTFail("Expected synced status after resync, got \(resolvedState.syncStatus)")
        }

        // Sequence should be nil (fresh start)
        XCTAssertNil(resolvedState.lastEventSequence)
        XCTAssertEqual(resolvedState.eventsSinceSnapshot, 0)
        XCTAssertEqual(resolvedState.containers["c1"]?.status, "Exited")
    }

    func testBatchApplyStopsAtFirstGap() {
        let container = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        let state = makeInitialState(containers: [container])

        // Batch: events 0, 1, 5, 6, 7 (gap after 1)
        let events = [
            makeEvent(sequence: 0, action: "start"),
            makeEvent(sequence: 1, action: "start"),
            makeEvent(sequence: 5, action: "stop"),
            makeEvent(sequence: 6, action: "start"),
            makeEvent(sequence: 7, action: "stop"),
        ]

        let (resultState, resultAction) = ContainerStateReducer.applyEvents(events, to: state)

        if case let .resyncRequired(reason) = resultAction {
            XCTAssertTrue(reason.contains("gap"))
        } else {
            XCTFail("Expected resyncRequired from batch, got \(resultAction)")
        }

        // Should have processed events 0 and 1, then stopped at 5
        XCTAssertEqual(resultState.lastEventSequence, 1, "Should stop at event 1 before the gap")
    }

    func testFreshSequenceAfterResyncAccepted() {
        let container = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        var state = makeInitialState(containers: [container])

        // Apply events 0..2
        for seq in UInt64(0) ... 2 {
            let (newState, _) = ContainerStateReducer.applyEvent(
                makeEvent(sequence: seq),
                to: state
            )
            state = newState
        }

        // Resync (resets sequence)
        let resyncContainer = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        state = ContainerStateReducer.applyResyncSnapshot(
            [resyncContainer],
            to: state,
            at: Date(timeIntervalSince1970: 1_001_000)
        )

        XCTAssertNil(state.lastEventSequence)

        // Fresh sequence starting at 0 should be accepted
        let (newState0, action0) = ContainerStateReducer.applyEvent(
            makeEvent(sequence: 0),
            to: state
        )
        XCTAssertEqual(action0, .none, "First event after resync should be accepted")
        XCTAssertEqual(newState0.lastEventSequence, 0)

        // Event 1 should follow normally
        let (newState1, action1) = ContainerStateReducer.applyEvent(
            makeEvent(sequence: 1),
            to: newState0
        )
        XCTAssertEqual(action1, .none)
        XCTAssertEqual(newState1.lastEventSequence, 1)
    }

    func testConcurrentAccessDuringResync() async {
        let holder = ContainerStateHolder()

        let container = ContainerSummaryFactory.make(id: "c1", name: "app", status: "Up")
        holder.applySnapshot([container], at: Date(timeIntervalSince1970: 1_000_000))

        // Concurrently apply events and resync to verify thread safety
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Apply events rapidly
            group.addTask {
                for seq in UInt64(0) ..< 100 {
                    holder.applyEvent(EventEnvelopeFactory.make(
                        sequence: seq,
                        containerId: "c1",
                        action: "start"
                    ))
                }
            }

            // Task 2: Trigger resyncs periodically
            group.addTask {
                for i in 0 ..< 10 {
                    let resyncContainer = ContainerSummaryFactory.make(
                        id: "c1",
                        name: "app",
                        status: "Up \(i)"
                    )
                    holder.applyResyncSnapshot(
                        [resyncContainer],
                        at: Date(timeIntervalSince1970: Double(1_001_000 + i))
                    )
                }
            }

            // Task 3: Read state concurrently
            group.addTask {
                for _ in 0 ..< 50 {
                    let state = holder.state
                    // Just verify we can read without crash
                    _ = state.containers.count
                    _ = state.syncStatus
                    _ = state.lastEventSequence
                }
            }
        }

        // After concurrent access, state should still be valid
        let finalState = holder.state
        XCTAssertEqual(finalState.containers.count, 1)
        XCTAssertNotNil(finalState.containers["c1"])
    }
}
