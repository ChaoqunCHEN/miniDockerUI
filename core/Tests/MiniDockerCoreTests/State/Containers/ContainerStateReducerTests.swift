import MiniDockerCore
import XCTest

final class ContainerStateReducerTests: XCTestCase {
    // MARK: - Helpers

    private func makeContainer(
        id: String, name: String, status: String = "Up",
        health: ContainerHealthStatus? = nil
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local", id: id, name: name,
            image: "alpine:3.20", status: status, health: health,
            labels: [:], startedAt: nil
        )
    }

    private func makeEvent(
        sequence: UInt64, action: String,
        containerId: String? = "c1",
        attributes: [String: String] = [:]
    ) -> EventEnvelope {
        EventEnvelope(
            sequence: sequence, eventAt: Date(),
            containerId: containerId, action: action,
            attributes: attributes, source: "test", raw: nil
        )
    }

    private func stateWithContainers(_ containers: [ContainerSummary], sequence: UInt64? = nil) -> ContainerState {
        let map = Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0) })
        return ContainerState(
            containers: map, syncStatus: .synced(since: Date()),
            lastEventSequence: sequence, lastSnapshotAt: Date(),
            eventsSinceSnapshot: 0
        )
    }

    // MARK: - Snapshot Tests

    func testApplySnapshotToEmptyState() {
        let containers = [makeContainer(id: "c1", name: "web"), makeContainer(id: "c2", name: "db")]
        let now = Date()
        let result = ContainerStateReducer.applySnapshot(containers, to: .empty, at: now)
        XCTAssertEqual(result.containerCount, 2)
        XCTAssertEqual(result.syncStatus, .synced(since: now))
        XCTAssertEqual(result.lastSnapshotAt, now)
        XCTAssertEqual(result.eventsSinceSnapshot, 0)
    }

    func testApplySnapshotReplacesExisting() {
        let old = [makeContainer(id: "old", name: "old")]
        let initial = ContainerStateReducer.applySnapshot(old, to: .empty, at: Date())
        let new = [makeContainer(id: "new", name: "new")]
        let result = ContainerStateReducer.applySnapshot(new, to: initial, at: Date())
        XCTAssertNil(result.container(byId: "old"))
        XCTAssertNotNil(result.container(byId: "new"))
        XCTAssertEqual(result.containerCount, 1)
    }

    func testApplySnapshotUpdatesTimestamp() {
        let now = Date()
        let result = ContainerStateReducer.applySnapshot([], to: .empty, at: now)
        XCTAssertEqual(result.lastSnapshotAt, now)
    }

    func testApplyEmptySnapshot() throws {
        let result = ContainerStateReducer.applySnapshot([], to: .empty, at: Date())
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.syncStatus, try .synced(since: XCTUnwrap(result.lastSnapshotAt)))
    }

    // MARK: - Single Event Tests

    func testApplyStartEventUpdatesStatus() throws {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", status: "Exited")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "start")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .none)
        XCTAssertTrue(try XCTUnwrap(newState.container(byId: "c1")?.isRunning))
    }

    func testApplyStopEventUpdatesStatus() throws {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", status: "Up")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "stop")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .none)
        XCTAssertFalse(try XCTUnwrap(newState.container(byId: "c1")?.isRunning))
    }

    func testApplyDieEventUpdatesStatus() throws {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", status: "Up")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "die")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .none)
        XCTAssertFalse(try XCTUnwrap(newState.container(byId: "c1")?.isRunning))
    }

    func testApplyDestroyEventRemovesContainer() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "destroy")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .containerRemoved(id: "c1"))
        XCTAssertNil(newState.container(byId: "c1"))
        XCTAssertTrue(newState.isEmpty)
    }

    func testApplyPauseEventUpdatesStatus() throws {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", status: "Up")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "pause")
        let (newState, _) = ContainerStateReducer.applyEvent(event, to: state)
        let status = try XCTUnwrap(newState.container(byId: "c1")?.status)
        XCTAssertTrue(status.contains("Paused"))
    }

    func testApplyUnpauseEventRestoresRunning() throws {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", status: "Up (Paused)")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "unpause")
        let (newState, _) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertTrue(try XCTUnwrap(newState.container(byId: "c1")?.isRunning))
    }

    func testApplyRenameEventUpdatesName() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "old-name")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "rename", attributes: ["name": "new-name"])
        let (newState, _) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(newState.container(byId: "c1")?.name, "new-name")
    }

    func testApplyHealthStatusEventUpdatesHealth() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web", health: .starting)], sequence: 0)
        let event = makeEvent(sequence: 1, action: "health_status", attributes: ["health_status": "healthy"])
        let (newState, _) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(newState.container(byId: "c1")?.health, .healthy)
    }

    func testApplyEventForUnknownContainer() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "start", containerId: "unknown")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .none)
        // Container "unknown" not in state, so state unchanged except sequence
        XCTAssertEqual(newState.containerCount, 1)
        XCTAssertEqual(newState.lastEventSequence, 1)
    }

    func testApplyUnclassifiedEventReturnsIgnored() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "exec_start")
        let (_, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .ignored(reason: "Unrecognized action: exec_start"))
    }

    func testApplyEventWithNilContainerId() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let event = makeEvent(sequence: 1, action: "start", containerId: nil)
        let (_, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .ignored(reason: "Event has no container ID"))
    }

    func testApplyCreateEventReturnsIgnored() {
        let state = stateWithContainers([], sequence: 0)
        let event = makeEvent(sequence: 1, action: "create")
        let (_, action) = ContainerStateReducer.applyEvent(event, to: state)
        XCTAssertEqual(action, .ignored(reason: "Create event; container will appear on start or snapshot"))
    }

    // MARK: - Sequence Gap Tests

    func testSequenceGapDetected() {
        XCTAssertTrue(ContainerStateReducer.hasSequenceGap(eventSequence: 5, lastKnownSequence: 3))
    }

    func testNoGapOnConsecutiveSequence() {
        XCTAssertFalse(ContainerStateReducer.hasSequenceGap(eventSequence: 4, lastKnownSequence: 3))
    }

    func testNoGapOnFirstEvent() {
        XCTAssertFalse(ContainerStateReducer.hasSequenceGap(eventSequence: 0, lastKnownSequence: nil))
    }

    func testApplyEventWithSequenceGapTriggersResync() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 3)
        let event = makeEvent(sequence: 10, action: "start")
        let (newState, action) = ContainerStateReducer.applyEvent(event, to: state)
        if case .resyncRequired = action {
            // Expected
        } else {
            XCTFail("Expected resyncRequired, got \(action)")
        }
        XCTAssertEqual(newState.syncStatus, .resyncRequired(reason: "Sequence gap: expected 4, got 10"))
    }

    func testBatchApplyStopsOnGap() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let events = [
            makeEvent(sequence: 1, action: "start"),
            makeEvent(sequence: 5, action: "stop"), // gap
            makeEvent(sequence: 6, action: "start"),
        ]
        let (newState, action) = ContainerStateReducer.applyEvents(events, to: state)
        if case .resyncRequired = action {
            // Expected
        } else {
            XCTFail("Expected resyncRequired, got \(action)")
        }
        // Should have applied first event but stopped at gap
        XCTAssertEqual(newState.lastEventSequence, 1)
    }

    // MARK: - Disconnect/Reconnect Tests

    func testMarkDisconnected() {
        let now = Date()
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")])
        let result = ContainerStateReducer.markDisconnected(state, at: now)
        XCTAssertEqual(result.syncStatus, .disconnected(at: now))
        XCTAssertEqual(result.containerCount, 1) // containers preserved
    }

    func testApplyResyncSnapshot() {
        let state = stateWithContainers([makeContainer(id: "old", name: "old")], sequence: 10)
        let now = Date()
        let newContainers = [makeContainer(id: "new", name: "new")]
        let result = ContainerStateReducer.applyResyncSnapshot(newContainers, to: state, at: now)
        XCTAssertNil(result.container(byId: "old"))
        XCTAssertNotNil(result.container(byId: "new"))
        XCTAssertNil(result.lastEventSequence) // reset
        XCTAssertEqual(result.syncStatus, .synced(since: now))
        XCTAssertEqual(result.eventsSinceSnapshot, 0)
    }

    func testResyncFromDisconnectedState() {
        let state = ContainerStateReducer.markDisconnected(
            stateWithContainers([makeContainer(id: "c1", name: "web")]),
            at: Date()
        )
        let now = Date()
        let result = ContainerStateReducer.applyResyncSnapshot(
            [makeContainer(id: "c1", name: "web-updated")],
            to: state, at: now
        )
        XCTAssertEqual(result.syncStatus, .synced(since: now))
        XCTAssertEqual(result.container(byId: "c1")?.name, "web-updated")
    }

    // MARK: - Event Counter Tests

    func testEventsSinceSnapshotIncrements() {
        let state = stateWithContainers([makeContainer(id: "c1", name: "web")], sequence: 0)
        let (s1, _) = ContainerStateReducer.applyEvent(makeEvent(sequence: 1, action: "start"), to: state)
        XCTAssertEqual(s1.eventsSinceSnapshot, 1)
        let (s2, _) = ContainerStateReducer.applyEvent(makeEvent(sequence: 2, action: "stop"), to: s1)
        XCTAssertEqual(s2.eventsSinceSnapshot, 2)
    }
}
