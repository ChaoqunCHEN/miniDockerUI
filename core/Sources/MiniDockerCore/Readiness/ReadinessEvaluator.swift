import Foundation
import os

/// Evaluates container readiness based on health status and/or regex
/// matching against log entries.
///
/// The evaluator is stateless and pure — it takes observations and a
/// rule, and returns a ``ReadinessResult``. The caller is responsible
/// for computing `windowStart` based on the rule's
/// ``ReadinessWindowStartPolicy``.
public struct ReadinessEvaluator: Sendable {
    /// Thread-safe cache for compiled regular expressions keyed by pattern string.
    private static let regexCache = OSAllocatedUnfairLock(
        initialState: [String: NSRegularExpression]()
    )

    public init() {}

    /// Evaluate readiness for the given rule and observations.
    ///
    /// - Throws: ``CoreError/contractViolation(expected:actual:)`` if the
    ///           regex pattern in the rule is invalid.
    public func evaluate(
        rule: ReadinessRule,
        healthStatus: ContainerHealthStatus?,
        logEntries: [LogEntry],
        windowStart: Date
    ) throws -> ReadinessResult {
        switch rule.mode {
        case .healthOnly:
            return evaluateHealthOnly(healthStatus: healthStatus)
        case .regexOnly:
            return try evaluateRegexOnly(
                rule: rule,
                logEntries: logEntries,
                windowStart: windowStart
            )
        case .healthThenRegex:
            return try evaluateHealthThenRegex(
                rule: rule,
                healthStatus: healthStatus,
                logEntries: logEntries,
                windowStart: windowStart
            )
        }
    }

    // MARK: - Mode Implementations

    private func evaluateHealthOnly(
        healthStatus: ContainerHealthStatus?
    ) -> ReadinessResult {
        let satisfied = healthStatus == .healthy
        return ReadinessResult(
            isReady: satisfied,
            healthSatisfied: satisfied,
            regexMatchCount: 0,
            evaluatedEntries: 0,
            rejectedStaleEntries: 0
        )
    }

    private func evaluateRegexOnly(
        rule: ReadinessRule,
        logEntries: [LogEntry],
        windowStart: Date
    ) throws -> ReadinessResult {
        let (matchCount, evaluated, rejected) = try countRegexMatches(
            rule: rule,
            logEntries: logEntries,
            windowStart: windowStart
        )
        return ReadinessResult(
            isReady: matchCount >= rule.mustMatchCount,
            healthSatisfied: false,
            regexMatchCount: matchCount,
            evaluatedEntries: evaluated,
            rejectedStaleEntries: rejected
        )
    }

    private func evaluateHealthThenRegex(
        rule: ReadinessRule,
        healthStatus: ContainerHealthStatus?,
        logEntries: [LogEntry],
        windowStart: Date
    ) throws -> ReadinessResult {
        // Short-circuit on healthy
        if healthStatus == .healthy {
            return evaluateHealthOnly(healthStatus: healthStatus)
        }

        // Fall back to regex
        return try evaluateRegexOnly(
            rule: rule,
            logEntries: logEntries,
            windowStart: windowStart
        )
    }

    // MARK: - Regex Matching

    private func cachedRegex(for pattern: String) throws -> NSRegularExpression {
        if let cached = Self.regexCache.withLock({ $0[pattern] }) {
            return cached
        }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            Self.regexCache.withLock { $0[pattern] = regex }
            return regex
        } catch {
            throw CoreError.contractViolation(
                expected: "valid regex pattern",
                actual: "invalid pattern: \(pattern)"
            )
        }
    }

    private func countRegexMatches(
        rule: ReadinessRule,
        logEntries: [LogEntry],
        windowStart: Date
    ) throws -> (matchCount: Int, evaluated: Int, rejected: Int) {
        guard let pattern = rule.regexPattern else {
            return (0, 0, 0)
        }

        let regex = try cachedRegex(for: pattern)

        var matchCount = 0
        var evaluated = 0
        var rejected = 0

        for entry in logEntries {
            if entry.timestamp < windowStart {
                rejected += 1
                continue
            }
            evaluated += 1
            let range = NSRange(entry.message.startIndex..., in: entry.message)
            if regex.firstMatch(in: entry.message, range: range) != nil {
                matchCount += 1
            }
        }

        return (matchCount, evaluated, rejected)
    }
}
