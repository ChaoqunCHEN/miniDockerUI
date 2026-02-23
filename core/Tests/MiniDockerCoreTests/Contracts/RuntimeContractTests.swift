import Foundation
@testable import MiniDockerCore
import XCTest

final class RuntimeContractTests: XCTestCase {
    func testEngineAdapterContractCompilesAndStreams() async throws {
        let adapter = StubEngineAdapter()
        let contract: any EngineAdapter = adapter

        let listed = try await contract.listContainers()
        XCTAssertEqual(listed.count, 1)

        let inspected = try await contract.inspectContainer(id: "c1")
        XCTAssertEqual(inspected.summary.id, "c1")

        var events: [EventEnvelope] = []
        for try await event in contract.streamEvents(since: nil) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 1)

        var logs: [LogEntry] = []
        for try await log in contract.streamLogs(
            id: "c1",
            options: LogStreamOptions(
                since: nil,
                tail: 10,
                includeStdout: true,
                includeStderr: true,
                timestamps: true,
                follow: false
            )
        ) {
            logs.append(log)
        }
        XCTAssertEqual(logs.count, 1)
    }

    func testAppSettingsStoreContractRoundTrip() throws {
        let expected = AppSettingsSnapshot(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: ["local:c1"],
            actionPreferences: ["default": "inspect"],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )
        let store = InMemorySettingsStore(snapshot: expected)
        let contract: any AppSettingsStore = store

        XCTAssertEqual(try contract.load(), expected)
    }
}

private struct StubEngineAdapter: EngineAdapter {
    func listContainers() async throws -> [ContainerSummary] {
        [
            ContainerSummary(
                engineContextId: "local",
                id: "c1",
                name: "web",
                image: "nginx:latest",
                status: "running",
                health: .healthy,
                labels: [:],
                startedAt: Date(timeIntervalSince1970: 1)
            ),
        ]
    }

    func inspectContainer(id: String) async throws -> ContainerDetail {
        let summary = ContainerSummary(
            engineContextId: "local",
            id: id,
            name: "web",
            image: "nginx:latest",
            status: "running",
            health: .healthy,
            labels: ["service": "web"],
            startedAt: Date(timeIntervalSince1970: 1)
        )

        return ContainerDetail(
            summary: summary,
            mounts: [ContainerMount(source: "/tmp", destination: "/data", mode: "rw", isReadOnly: false)],
            networkSettings: ContainerNetworkSettings(
                networkMode: "bridge",
                ipAddressesByNetwork: ["bridge": "172.18.0.2"],
                ports: [ContainerPortBinding(containerPort: "80/tcp", hostIP: "0.0.0.0", hostPort: 8080)]
            ),
            healthDetail: nil,
            rawInspect: .object(["Id": .string(id)])
        )
    }

    func startContainer(id _: String) async throws {}

    func stopContainer(id _: String, timeoutSeconds _: Int?) async throws {}

    func restartContainer(id _: String, timeoutSeconds _: Int?) async throws {}

    func streamEvents(since _: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                EventEnvelope(
                    sequence: 1,
                    eventAt: Date(timeIntervalSince1970: 2),
                    containerId: "c1",
                    action: "start",
                    attributes: ["name": "web"],
                    source: "docker",
                    raw: .object(["status": .string("start")])
                )
            )
            continuation.finish()
        }
    }

    func streamLogs(id: String, options _: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                LogEntry(
                    engineContextId: "local",
                    containerId: id,
                    stream: .stdout,
                    timestamp: Date(timeIntervalSince1970: 3),
                    message: "ready"
                )
            )
            continuation.finish()
        }
    }
}

private final class InMemorySettingsStore: AppSettingsStore {
    private let snapshot: AppSettingsSnapshot

    init(snapshot: AppSettingsSnapshot) {
        self.snapshot = snapshot
    }

    func load() throws -> AppSettingsSnapshot {
        snapshot
    }

    func save(_: AppSettingsSnapshot) throws {}
}
