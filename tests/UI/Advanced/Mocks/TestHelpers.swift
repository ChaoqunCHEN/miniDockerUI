import Foundation
@testable import MiniDockerCore

enum TestHelpers {
    static func makeLogEntry(
        containerId: String = "test-container",
        stream: LogStream = .stdout,
        timestamp: Date = Date(),
        message: String = "test message"
    ) -> LogEntry {
        LogEntry(
            engineContextId: "local",
            containerId: containerId,
            stream: stream,
            timestamp: timestamp,
            message: message
        )
    }

    static func makeContainerSummary(
        id: String = "test-container",
        name: String = "test-name",
        status: String = "Up",
        health: ContainerHealthStatus? = nil,
        startedAt: Date? = nil
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local",
            id: id,
            name: name,
            image: "alpine:3.20",
            status: status,
            health: health,
            labels: [:],
            startedAt: startedAt
        )
    }

    static func makeContainerDetail(
        id: String = "test-container",
        name: String = "test-name",
        status: String = "Up",
        health: ContainerHealthStatus? = nil,
        healthDetail: ContainerHealthDetail? = nil,
        startedAt: Date? = nil
    ) -> ContainerDetail {
        let summary = makeContainerSummary(
            id: id,
            name: name,
            status: status,
            health: health,
            startedAt: startedAt
        )
        return ContainerDetail(
            summary: summary,
            mounts: [],
            networkSettings: ContainerNetworkSettings(
                networkMode: "bridge",
                ipAddressesByNetwork: [:],
                ports: []
            ),
            healthDetail: healthDetail,
            rawInspect: .object([:])
        )
    }

    static func makeLogBuffer(
        maxLines: Int = 10000,
        maxBytes: Int = 1_024_000
    ) -> LogRingBuffer {
        LogRingBuffer(policy: LogBufferPolicy(
            maxLinesPerContainer: maxLines,
            maxBytesPerContainer: maxBytes,
            dropStrategy: .dropOldest,
            flushHz: 30
        ))
    }
}
