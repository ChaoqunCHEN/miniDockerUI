import Foundation

/// Signals what the caller should do after a reduce operation.
public enum ReconcileAction: Sendable, Equatable {
    case none
    case resyncRequired(reason: String)
    case containerRemoved(id: String)
    case ignored(reason: String)
}

/// Pure-function reducer for container state reconciliation.
/// All methods are static and side-effect-free.
public struct ContainerStateReducer: Sendable {
    private init() {}

    // MARK: - Snapshot Operations

    /// Apply an initial or refresh snapshot, replacing all container data.
    public static func applySnapshot(
        _ snapshot: [ContainerSummary],
        to state: ContainerState,
        at timestamp: Date
    ) -> ContainerState {
        let map = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        return ContainerState(
            containers: map,
            syncStatus: .synced(since: timestamp),
            lastEventSequence: state.lastEventSequence,
            lastSnapshotAt: timestamp,
            eventsSinceSnapshot: 0
        )
    }

    // MARK: - Event Operations

    /// Apply a single event to the current state.
    public static func applyEvent(
        _ event: EventEnvelope,
        to state: ContainerState
    ) -> (ContainerState, ReconcileAction) {
        // Sequence gap check
        if hasSequenceGap(eventSequence: event.sequence, lastKnownSequence: state.lastEventSequence) {
            let reason = "Sequence gap: expected \((state.lastEventSequence ?? 0) + 1), got \(event.sequence)"
            let newState = ContainerState(
                containers: state.containers,
                syncStatus: .resyncRequired(reason: reason),
                lastEventSequence: state.lastEventSequence,
                lastSnapshotAt: state.lastSnapshotAt,
                eventsSinceSnapshot: state.eventsSinceSnapshot
            )
            return (newState, .resyncRequired(reason: reason))
        }

        guard let containerId = event.containerId else {
            let newState = stateWithUpdatedSequence(state, sequence: event.sequence)
            return (newState, .ignored(reason: "Event has no container ID"))
        }

        guard let eventType = ContainerEvent.classify(event.action) else {
            let newState = stateWithUpdatedSequence(state, sequence: event.sequence)
            return (newState, .ignored(reason: "Unrecognized action: \(event.action)"))
        }

        var containers = state.containers

        switch eventType {
        case .create:
            let newState = stateWithUpdatedSequence(state, sequence: event.sequence)
            return (newState, .ignored(reason: "Create event; container will appear on start or snapshot"))

        case .start:
            if let existing = containers[containerId] {
                containers[containerId] = updatedContainer(existing, status: "Up")
            }

        case .stop, .die:
            if let existing = containers[containerId] {
                containers[containerId] = updatedContainer(existing, status: "Exited")
            }

        case .destroy:
            containers.removeValue(forKey: containerId)
            let newState = ContainerState(
                containers: containers,
                syncStatus: state.syncStatus,
                lastEventSequence: event.sequence,
                lastSnapshotAt: state.lastSnapshotAt,
                eventsSinceSnapshot: state.eventsSinceSnapshot + 1
            )
            return (newState, .containerRemoved(id: containerId))

        case .pause:
            if let existing = containers[containerId] {
                containers[containerId] = updatedContainer(existing, status: "Up (Paused)")
            }

        case .unpause:
            if let existing = containers[containerId] {
                containers[containerId] = updatedContainer(existing, status: "Up")
            }

        case .rename:
            if let existing = containers[containerId],
               let newName = event.attributes["name"]
            {
                containers[containerId] = updatedContainer(existing, name: newName)
            }

        case .healthStatus:
            if let existing = containers[containerId],
               let healthStr = event.attributes["health_status"],
               let health = ContainerHealthStatus(rawValue: healthStr)
            {
                containers[containerId] = updatedContainer(existing, health: health)
            }
        }

        let newState = ContainerState(
            containers: containers,
            syncStatus: state.syncStatus,
            lastEventSequence: event.sequence,
            lastSnapshotAt: state.lastSnapshotAt,
            eventsSinceSnapshot: state.eventsSinceSnapshot + 1
        )
        return (newState, .none)
    }

    /// Apply a batch of events in order.
    /// Stops and returns `.resyncRequired` if a sequence gap is detected.
    public static func applyEvents(
        _ events: [EventEnvelope],
        to state: ContainerState
    ) -> (ContainerState, ReconcileAction) {
        var current = state
        for event in events {
            let (newState, action) = applyEvent(event, to: current)
            current = newState
            if case .resyncRequired = action {
                return (current, action)
            }
        }
        return (current, .none)
    }

    // MARK: - Disconnect / Reconnect

    /// Mark state as disconnected (event stream lost).
    public static func markDisconnected(
        _ state: ContainerState,
        at timestamp: Date
    ) -> ContainerState {
        ContainerState(
            containers: state.containers,
            syncStatus: .disconnected(at: timestamp),
            lastEventSequence: state.lastEventSequence,
            lastSnapshotAt: state.lastSnapshotAt,
            eventsSinceSnapshot: state.eventsSinceSnapshot
        )
    }

    /// Merge a resync snapshot after reconnect.
    /// Full replacement: new snapshot is authoritative.
    public static func applyResyncSnapshot(
        _ snapshot: [ContainerSummary],
        to _: ContainerState,
        at timestamp: Date
    ) -> ContainerState {
        let map = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        return ContainerState(
            containers: map,
            syncStatus: .synced(since: timestamp),
            lastEventSequence: nil,
            lastSnapshotAt: timestamp,
            eventsSinceSnapshot: 0
        )
    }

    // MARK: - Sequence Gap Detection

    /// Check if an event's sequence indicates a gap from the last known sequence.
    public static func hasSequenceGap(
        eventSequence: UInt64,
        lastKnownSequence: UInt64?
    ) -> Bool {
        guard let last = lastKnownSequence else { return false }
        return eventSequence != last + 1
    }

    // MARK: - Private Helpers

    private static func stateWithUpdatedSequence(
        _ state: ContainerState,
        sequence: UInt64
    ) -> ContainerState {
        ContainerState(
            containers: state.containers,
            syncStatus: state.syncStatus,
            lastEventSequence: sequence,
            lastSnapshotAt: state.lastSnapshotAt,
            eventsSinceSnapshot: state.eventsSinceSnapshot + 1
        )
    }

    private static func updatedContainer(
        _ container: ContainerSummary,
        status: String? = nil,
        health: ContainerHealthStatus? = nil,
        name: String? = nil
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: container.engineContextId,
            id: container.id,
            name: name ?? container.name,
            image: container.image,
            status: status ?? container.status,
            health: health ?? container.health,
            labels: container.labels,
            startedAt: container.startedAt
        )
    }
}
