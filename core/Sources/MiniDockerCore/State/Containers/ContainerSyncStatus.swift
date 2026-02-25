import Foundation

/// Represents the current synchronization lifecycle phase for container state.
public enum ContainerSyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case synced(since: Date)
    case disconnected(at: Date)
    case resyncRequired(reason: String)
}
