import Foundation

/// Configuration for exponential backoff retry behavior.
///
/// Computes delays using `min(initialDelay * multiplier^attempt, maxDelay)`.
public struct BackoffPolicy: Sendable, Equatable {
    public let initialDelay: Duration
    public let maxDelay: Duration
    public let maxRetries: Int
    public let multiplier: Double

    public init(
        initialDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(30),
        maxRetries: Int = 10,
        multiplier: Double = 2.0
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.maxRetries = maxRetries
        self.multiplier = multiplier
    }

    /// Compute the delay for the given attempt (0-indexed).
    public func delay(forAttempt attempt: Int) -> Duration {
        guard attempt >= 0 else { return initialDelay }
        let initialSeconds = Double(initialDelay.components.seconds)
            + Double(initialDelay.components.attoseconds) / 1e18
        let maxSeconds = Double(maxDelay.components.seconds)
            + Double(maxDelay.components.attoseconds) / 1e18
        let computed = initialSeconds * pow(multiplier, Double(attempt))
        let clamped = min(computed, maxSeconds)
        let wholeSeconds = Int64(clamped)
        let fractionalAtto = Int64((clamped - Double(wholeSeconds)) * 1e18)
        return Duration(secondsComponent: wholeSeconds, attosecondsComponent: fractionalAtto)
    }
}
