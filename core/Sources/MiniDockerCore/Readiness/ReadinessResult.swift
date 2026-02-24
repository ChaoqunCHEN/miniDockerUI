import Foundation

/// Outcome of a readiness evaluation against a ``ReadinessRule``.
public struct ReadinessResult: Sendable, Equatable {
    /// Whether the container is considered ready.
    public let isReady: Bool

    /// Whether the health check alone was satisfied.
    public let healthSatisfied: Bool

    /// Number of log entries matching the regex pattern.
    public let regexMatchCount: Int

    /// Number of log entries evaluated (after stale-line filtering).
    public let evaluatedEntries: Int

    /// Number of log entries rejected because they preceded the window start.
    public let rejectedStaleEntries: Int

    public init(
        isReady: Bool,
        healthSatisfied: Bool,
        regexMatchCount: Int,
        evaluatedEntries: Int,
        rejectedStaleEntries: Int
    ) {
        self.isReady = isReady
        self.healthSatisfied = healthSatisfied
        self.regexMatchCount = regexMatchCount
        self.evaluatedEntries = evaluatedEntries
        self.rejectedStaleEntries = rejectedStaleEntries
    }
}
