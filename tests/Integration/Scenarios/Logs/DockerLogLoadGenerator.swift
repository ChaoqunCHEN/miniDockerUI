import Foundation
@testable import MiniDockerCore

// MARK: - Synthetic Log Load Generator

/// Generates `LogEntry` arrays in memory for testing log burst scenarios.
/// Implements the `LogLoadGenerator` protocol from TestContracts.
struct SyntheticLogLoadGenerator: LogLoadGenerator, Sendable {
    func generate(containerId _: String, profile: LogLoadProfile) async throws -> LogLoadResult {
        let startedAt = Date()
        var totalBytes = 0

        let padding = String(repeating: "A", count: max(0, profile.bytesPerLine - 30))

        for i in 0 ..< profile.lineCount {
            let message = "log-\(String(format: "%08d", i))-\(padding)"
            totalBytes += message.utf8.count

            if profile.intervalMilliseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(profile.intervalMilliseconds) * 1_000_000)
            }
        }

        let finishedAt = Date()

        return LogLoadResult(
            generatedLines: profile.lineCount,
            generatedBytes: totalBytes,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}

// MARK: - Log Load Generator That Populates a Buffer

/// Extended generator that produces log entries and appends them directly
/// to a `LogRingBuffer`, returning the result.
struct BufferPopulatingLogLoadGenerator: Sendable {
    let buffer: LogRingBuffer

    func generate(containerId: String, profile: LogLoadProfile) -> LogLoadResult {
        let startedAt = Date()
        let padding = String(repeating: "A", count: max(0, profile.bytesPerLine - 30))
        var totalBytes = 0

        for i in 0 ..< profile.lineCount {
            let message = "log-\(String(format: "%08d", i))-\(padding)"
            let entry = LogEntry(
                engineContextId: "integ-ctx",
                containerId: containerId,
                stream: i % 10 == 0 ? .stderr : .stdout,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 0.001),
                message: message
            )
            buffer.append(entry)
            totalBytes += message.utf8.count
        }

        let finishedAt = Date()

        return LogLoadResult(
            generatedLines: profile.lineCount,
            generatedBytes: totalBytes,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}
