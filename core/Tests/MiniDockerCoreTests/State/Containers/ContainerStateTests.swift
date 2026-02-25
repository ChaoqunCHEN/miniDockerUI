import MiniDockerCore
import XCTest

final class ContainerStateTests: XCTestCase {
    private func makeContainer(id: String, name: String, status: String = "Up") -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local",
            id: id,
            name: name,
            image: "alpine:3.20",
            status: status,
            health: nil,
            labels: [:],
            startedAt: nil
        )
    }

    func testEmptyState() {
        let state = ContainerState.empty
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.containerCount, 0)
        XCTAssertEqual(state.syncStatus, .idle)
        XCTAssertNil(state.lastEventSequence)
        XCTAssertNil(state.lastSnapshotAt)
        XCTAssertEqual(state.eventsSinceSnapshot, 0)
        XCTAssertTrue(state.containerList.isEmpty)
    }

    func testContainerLookupById() {
        let c1 = makeContainer(id: "abc", name: "web")
        let state = ContainerState(
            containers: ["abc": c1],
            syncStatus: .idle,
            lastEventSequence: nil,
            lastSnapshotAt: nil,
            eventsSinceSnapshot: 0
        )
        XCTAssertEqual(state.container(byId: "abc"), c1)
        XCTAssertNil(state.container(byId: "xyz"))
    }

    func testContainerListSortedByName() {
        let c1 = makeContainer(id: "1", name: "zeta")
        let c2 = makeContainer(id: "2", name: "alpha")
        let c3 = makeContainer(id: "3", name: "mid")
        let state = ContainerState(
            containers: ["1": c1, "2": c2, "3": c3],
            syncStatus: .idle,
            lastEventSequence: nil,
            lastSnapshotAt: nil,
            eventsSinceSnapshot: 0
        )
        let names = state.containerList.map(\.name)
        XCTAssertEqual(names, ["alpha", "mid", "zeta"])
    }

    func testContainerCount() {
        let c1 = makeContainer(id: "1", name: "a")
        let c2 = makeContainer(id: "2", name: "b")
        let state = ContainerState(
            containers: ["1": c1, "2": c2],
            syncStatus: .idle,
            lastEventSequence: nil,
            lastSnapshotAt: nil,
            eventsSinceSnapshot: 0
        )
        XCTAssertEqual(state.containerCount, 2)
        XCTAssertFalse(state.isEmpty)
    }

    func testEquality() {
        let c1 = makeContainer(id: "1", name: "a")
        let now = Date()
        let state1 = ContainerState(
            containers: ["1": c1],
            syncStatus: .synced(since: now),
            lastEventSequence: 5,
            lastSnapshotAt: now,
            eventsSinceSnapshot: 3
        )
        let state2 = ContainerState(
            containers: ["1": c1],
            syncStatus: .synced(since: now),
            lastEventSequence: 5,
            lastSnapshotAt: now,
            eventsSinceSnapshot: 3
        )
        XCTAssertEqual(state1, state2)
    }

    func testInequalityOnDifferentContainers() {
        let c1 = makeContainer(id: "1", name: "a")
        let c2 = makeContainer(id: "2", name: "b")
        let state1 = ContainerState(
            containers: ["1": c1],
            syncStatus: .idle,
            lastEventSequence: nil,
            lastSnapshotAt: nil,
            eventsSinceSnapshot: 0
        )
        let state2 = ContainerState(
            containers: ["2": c2],
            syncStatus: .idle,
            lastEventSequence: nil,
            lastSnapshotAt: nil,
            eventsSinceSnapshot: 0
        )
        XCTAssertNotEqual(state1, state2)
    }
}
