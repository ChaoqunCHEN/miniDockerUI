import Foundation

/// Immutable snapshot of container state with reconciliation metadata.
public struct ContainerState: Sendable, Equatable {
    /// Containers keyed by container ID for O(1) lookup.
    public let containers: [String: ContainerSummary]

    /// Current sync lifecycle status.
    public let syncStatus: ContainerSyncStatus

    /// Monotonically increasing sequence of the last applied event.
    /// `nil` if no events have been applied yet.
    public let lastEventSequence: UInt64?

    /// Timestamp of the last successful snapshot load or resync.
    public let lastSnapshotAt: Date?

    /// Number of events applied since last snapshot.
    public let eventsSinceSnapshot: UInt64

    public init(
        containers: [String: ContainerSummary],
        syncStatus: ContainerSyncStatus,
        lastEventSequence: UInt64?,
        lastSnapshotAt: Date?,
        eventsSinceSnapshot: UInt64
    ) {
        self.containers = containers
        self.syncStatus = syncStatus
        self.lastEventSequence = lastEventSequence
        self.lastSnapshotAt = lastSnapshotAt
        self.eventsSinceSnapshot = eventsSinceSnapshot
    }

    /// Containers sorted by name.
    public var containerList: [ContainerSummary] {
        containers.values.sorted { $0.name < $1.name }
    }

    public var isEmpty: Bool {
        containers.isEmpty
    }

    public var containerCount: Int {
        containers.count
    }

    public func container(byId id: String) -> ContainerSummary? {
        containers[id]
    }

    public static let empty = ContainerState(
        containers: [:],
        syncStatus: .idle,
        lastEventSequence: nil,
        lastSnapshotAt: nil,
        eventsSinceSnapshot: 0
    )
}
