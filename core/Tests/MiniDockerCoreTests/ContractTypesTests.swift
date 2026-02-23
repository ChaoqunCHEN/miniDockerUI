import Foundation
@testable import MiniDockerCore
import XCTest

final class ContractTypesTests: XCTestCase {
    func testEngineAdapterContractCompiles() async throws {
        let adapter = EngineAdapterMock()

        let list = try await adapter.listContainers()
        XCTAssertEqual(list.count, 1)

        let detail = try await adapter.inspectContainer(id: "abc123")
        XCTAssertEqual(detail.summary.id, "abc123")

        try await adapter.startContainer(id: "abc123")
        try await adapter.stopContainer(id: "abc123", timeoutSeconds: 10)
        try await adapter.restartContainer(id: "abc123", timeoutSeconds: nil)
    }

    func testPublicContractsAndTypesShape() throws {
        let endpoint = EngineEndpoint(endpointType: .local, address: "unix:///var/run/docker.sock")
        XCTAssertEqual(endpoint.endpointType, .local)

        let mapping = WorktreeMapping(
            id: "map-1",
            repoRoot: "/repo",
            anchorPath: "/repo/current",
            targetType: .container,
            targetId: "abc123",
            restartPolicy: .ifRunning
        )

        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: ["abc123"],
            actionPreferences: ["abc123": "inspect"],
            worktreeMappings: [mapping],
            readinessRules: [
                "abc123": ReadinessRule(
                    mode: .healthOnly,
                    regexPattern: nil,
                    mustMatchCount: 1,
                    windowStartPolicy: .containerStart
                ),
            ],
            transientUIPreferences: [:]
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}

private struct EngineAdapterMock: EngineAdapter {
    func listContainers() async throws -> [ContainerSummary] {
        [ContainerSummary(
            engineContextId: "local",
            id: "abc123",
            name: "demo",
            image: "busybox:latest",
            status: "running",
            health: .healthy,
            labels: ["app": "demo"],
            startedAt: Date(timeIntervalSince1970: 0)
        )]
    }

    func inspectContainer(id: String) async throws -> ContainerDetail {
        let summary = ContainerSummary(
            engineContextId: "local",
            id: id,
            name: "demo",
            image: "busybox:latest",
            status: "running",
            health: .healthy,
            labels: [:],
            startedAt: nil
        )
        return ContainerDetail(
            summary: summary,
            mounts: [ContainerMount(source: "/tmp", destination: "/data", mode: "rw", isReadOnly: false)],
            networkSettings: ContainerNetworkSettings(
                networkMode: "bridge",
                ipAddressesByNetwork: ["bridge": "127.0.0.1"],
                ports: [ContainerPortBinding(containerPort: "8080/tcp", hostIP: "127.0.0.1", hostPort: 8080)]
            ),
            healthDetail: ContainerHealthDetail(status: .healthy, failingStreak: 0, logs: []),
            rawInspect: .object([:])
        )
    }

    func startContainer(id _: String) async throws {}
    func stopContainer(id _: String, timeoutSeconds _: Int?) async throws {}
    func restartContainer(id _: String, timeoutSeconds _: Int?) async throws {}

    func streamEvents(since _: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func streamLogs(id _: String, options _: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
