import MiniDockerCore
import XCTest

final class ContainerStateHolderTests: XCTestCase {
    private func makeContainer(id: String, name: String, status: String = "Up") -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local", id: id, name: name,
            image: "alpine:3.20", status: status, health: nil,
            labels: [:], startedAt: nil
        )
    }

    private func makeEvent(sequence: UInt64, action: String, containerId: String = "c1") -> EventEnvelope {
        EventEnvelope(
            sequence: sequence, eventAt: Date(),
            containerId: containerId, action: action,
            attributes: [:], source: "test", raw: nil
        )
    }

    func testInitialState() {
        let holder = ContainerStateHolder()
        XCTAssertTrue(holder.state.isEmpty)
        XCTAssertEqual(holder.state.syncStatus, .idle)
    }

    func testApplySnapshotUpdatesState() {
        let holder = ContainerStateHolder()
        let containers = [makeContainer(id: "c1", name: "web")]
        holder.applySnapshot(containers, at: Date())
        XCTAssertEqual(holder.state.containerCount, 1)
        XCTAssertNotNil(holder.state.container(byId: "c1"))
    }

    func testApplyEventUpdatesState() throws {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "c1", name: "web", status: "Exited")], at: Date())
        holder.applyEvent(makeEvent(sequence: 0, action: "start"))
        XCTAssertTrue(try XCTUnwrap(holder.state.container(byId: "c1")?.isRunning))
    }

    func testApplyEventReturnsAction() {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "c1", name: "web")], at: Date())
        let action = holder.applyEvent(makeEvent(sequence: 0, action: "destroy"))
        XCTAssertEqual(action, .containerRemoved(id: "c1"))
    }

    func testMarkDisconnectedUpdatesState() {
        let holder = ContainerStateHolder()
        let now = Date()
        holder.markDisconnected(at: now)
        XCTAssertEqual(holder.state.syncStatus, .disconnected(at: now))
    }

    func testResyncUpdatesState() {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "old", name: "old")], at: Date())
        holder.applyResyncSnapshot([makeContainer(id: "new", name: "new")], at: Date())
        XCTAssertNil(holder.state.container(byId: "old"))
        XCTAssertNotNil(holder.state.container(byId: "new"))
    }

    func testConcurrentReads() async {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "c1", name: "web")], at: Date())

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    _ = holder.state.containerCount
                }
            }
        }
        // No crash = pass
        XCTAssertEqual(holder.state.containerCount, 1)
    }

    func testConcurrentWriteAndRead() async {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "c1", name: "web", status: "Exited")], at: Date())

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0 ..< 50 {
                group.addTask {
                    let event = EventEnvelope(
                        sequence: UInt64(i), eventAt: Date(),
                        containerId: "c1", action: i % 2 == 0 ? "start" : "stop",
                        attributes: [:], source: "test", raw: nil
                    )
                    holder.applyEvent(event)
                }
            }
            // Readers
            for _ in 0 ..< 50 {
                group.addTask {
                    _ = holder.state.containerList
                }
            }
        }
        // No crash or deadlock = pass
        XCTAssertEqual(holder.state.containerCount, 1)
    }

    func testSequentialEventBatch() throws {
        let holder = ContainerStateHolder()
        holder.applySnapshot([makeContainer(id: "c1", name: "web", status: "Exited")], at: Date())
        let events = [
            makeEvent(sequence: 0, action: "start"),
            makeEvent(sequence: 1, action: "stop"),
            makeEvent(sequence: 2, action: "start"),
        ]
        let action = holder.applyEvents(events)
        XCTAssertEqual(action, .none)
        XCTAssertTrue(try XCTUnwrap(holder.state.container(byId: "c1")?.isRunning))
        XCTAssertEqual(holder.state.lastEventSequence, 2)
    }
}
