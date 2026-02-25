import Foundation

/// Deterministic state machine for stream supervisor lifecycle.
public enum SupervisorPhase: Sendable, Equatable {
    case idle
    case connecting
    case streaming
    case disconnected(at: Date, attempt: Int)
    case backingOff(until: Date, attempt: Int)
    case resyncing
    case exhausted(totalAttempts: Int)
    case stopped
}
