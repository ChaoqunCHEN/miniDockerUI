import Foundation

/// Events emitted by the ``EventStreamSupervisor`` to its consumer.
public enum SupervisorEvent: Sendable {
    /// A domain event from the Docker event stream.
    case dockerEvent(EventEnvelope)

    /// Supervisor phase changed (for UI status display).
    case phaseChanged(SupervisorPhase)

    /// A full container list resync completed after reconnect.
    case resyncCompleted(containers: [ContainerSummary], at: Date)
}
