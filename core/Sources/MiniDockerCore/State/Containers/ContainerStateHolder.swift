import Foundation
import os

/// Thread-safe, lock-protected holder for `ContainerState`.
public final class ContainerStateHolder: Sendable {
    private let lock: OSAllocatedUnfairLock<ContainerState>

    public init(initialState: ContainerState = .empty) {
        lock = OSAllocatedUnfairLock(initialState: initialState)
    }

    /// Current state snapshot (read under lock).
    public var state: ContainerState {
        lock.withLock { $0 }
    }

    /// Apply a snapshot (initial load or resync).
    public func applySnapshot(_ containers: [ContainerSummary], at timestamp: Date) {
        lock.withLock { current in
            current = ContainerStateReducer.applySnapshot(containers, to: current, at: timestamp)
        }
    }

    /// Apply a single event. Returns the reconcile action.
    @discardableResult
    public func applyEvent(_ event: EventEnvelope) -> ReconcileAction {
        lock.withLock { current in
            let (newState, action) = ContainerStateReducer.applyEvent(event, to: current)
            current = newState
            return action
        }
    }

    /// Apply batch of events. Returns the reconcile action.
    @discardableResult
    public func applyEvents(_ events: [EventEnvelope]) -> ReconcileAction {
        lock.withLock { current in
            let (newState, action) = ContainerStateReducer.applyEvents(events, to: current)
            current = newState
            return action
        }
    }

    /// Mark as disconnected.
    public func markDisconnected(at timestamp: Date) {
        lock.withLock { current in
            current = ContainerStateReducer.markDisconnected(current, at: timestamp)
        }
    }

    /// Apply resync snapshot after reconnect.
    public func applyResyncSnapshot(_ containers: [ContainerSummary], at timestamp: Date) {
        lock.withLock { current in
            current = ContainerStateReducer.applyResyncSnapshot(containers, to: current, at: timestamp)
        }
    }
}
