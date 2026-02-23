import Foundation
@testable import MiniDockerCore
import XCTest

final class ModelTypeContractTests: XCTestCase {
    func testContainerActionContractMatchesArchitectureCases() {
        XCTAssertEqual(
            Set(ContainerAction.allCases.map(\.rawValue)),
            Set(["start", "stop", "restart", "viewLogs", "inspect"])
        )
    }

    func testReadinessModeContractMatchesArchitectureCases() {
        XCTAssertEqual(
            Set(ReadinessMode.allCases.map(\.rawValue)),
            Set(["healthOnly", "healthThenRegex", "regexOnly"])
        )
    }

    func testJSONValueCodableRoundTrip() throws {
        let value: JSONValue = .object([
            "status": .string("running"),
            "attempts": .number(3),
            "healthy": .bool(true),
            "nested": .array([.null, .string("ok")]),
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testContainerDetailCodableRoundTrip() throws {
        let detail = makeContainerDetailFixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(detail)
        let decoded = try decoder.decode(ContainerDetail.self, from: data)
        XCTAssertEqual(decoded, detail)
    }

    func testAppSettingsSnapshotContractShape() throws {
        let snapshot = AppSettingsSnapshot(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: ["local:container-1"],
            actionPreferences: ["container-1": "viewLogs"],
            worktreeMappings: [
                WorktreeMapping(
                    id: "m1",
                    repoRoot: "/repo",
                    anchorPath: "/repo/current",
                    targetType: .container,
                    targetId: "container-1",
                    restartPolicy: .ifRunning
                ),
            ],
            readinessRules: [
                "container-1": ReadinessRule(
                    mode: .healthThenRegex,
                    regexPattern: "ready",
                    mustMatchCount: 1,
                    windowStartPolicy: .containerStart
                ),
            ],
            transientUIPreferences: ["split": .number(0.4)]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, "1.0.0")
        XCTAssertEqual(decoded.favoriteContainerKeys, ["local:container-1"])
        XCTAssertEqual(decoded.worktreeMappings.first?.targetId, "container-1")
    }
}

private func makeContainerDetailFixture() -> ContainerDetail {
    let started = Date(timeIntervalSince1970: 123)
    let finished = Date(timeIntervalSince1970: 124)
    let summary = ContainerSummary(
        engineContextId: "local",
        id: "container-1",
        name: "api",
        image: "my/api:latest",
        status: "running",
        health: .healthy,
        labels: ["tier": "backend"],
        startedAt: started
    )

    return ContainerDetail(
        summary: summary,
        mounts: [ContainerMount(source: "/tmp/src", destination: "/app", mode: "rw", isReadOnly: false)],
        networkSettings: ContainerNetworkSettings(
            networkMode: "bridge",
            ipAddressesByNetwork: ["bridge": "172.18.0.4"],
            ports: [ContainerPortBinding(containerPort: "8080/tcp", hostIP: "127.0.0.1", hostPort: 18080)]
        ),
        healthDetail: ContainerHealthDetail(
            status: .healthy,
            failingStreak: 0,
            logs: [ContainerHealthLog(startedAt: started, endedAt: finished, exitCode: 0, output: "ok")]
        ),
        rawInspect: .object(["Id": .string("container-1"), "State": .object(["Status": .string("running")])])
    )
}
