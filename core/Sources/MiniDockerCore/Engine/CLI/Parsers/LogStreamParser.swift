import Foundation

/// Parses timestamped log lines from `docker logs -t`.
///
/// Each line has the format: `<RFC3339Nano timestamp> <message>`.
/// The parser splits on the first space after the timestamp and creates
/// a ``LogEntry`` with the parsed timestamp and raw message.
public struct LogStreamParser: Sendable {
    public init() {}

    /// Parse a single timestamped log line.
    ///
    /// - Parameters:
    ///   - line: A single line from `docker logs -t` output.
    ///   - engineContextId: The engine context ID.
    ///   - containerId: The container this log belongs to.
    ///   - defaultStream: Stream to use (stdout/stderr/system).
    public func parseLogLine(
        line: String,
        engineContextId: String,
        containerId: String,
        defaultStream: LogStream
    ) throws -> LogEntry {
        // Find the first space that separates the timestamp from the message.
        // Timestamp format: 2026-02-22T10:30:00.123456789Z
        // Minimum timestamp length is ~20 chars (without fractional seconds).
        guard let spaceIndex = findTimestampEnd(in: line) else {
            throw CoreError.outputParseFailure(
                context: "docker logs timestamp",
                rawSnippet: String(line.prefix(200))
            )
        }

        let timestampStr = String(line[line.startIndex ..< spaceIndex])
        let message = String(line[line.index(after: spaceIndex)...])

        guard let timestamp = DockerDateParser.parseRFC3339Nano(timestampStr) else {
            throw CoreError.outputParseFailure(
                context: "docker logs malformed timestamp",
                rawSnippet: String(line.prefix(200))
            )
        }

        let (stripped, spans) = ANSIParser.parse(message)

        return LogEntry(
            engineContextId: engineContextId,
            containerId: containerId,
            stream: defaultStream,
            timestamp: timestamp,
            message: stripped,
            styledSpans: spans
        )
    }

    // MARK: - Private

    /// Find the index of the space character that terminates the RFC3339 timestamp.
    ///
    /// We look for a space that appears after a 'Z', '+', or '-' timezone indicator
    /// that follows the time portion. This handles both `...Z message` and `...+00:00 message`.
    private func findTimestampEnd(in line: String) -> String.Index? {
        // The timestamp must contain at least a 'T' separator
        guard line.contains("T") else { return nil }

        // Find the first space after position 19 (minimum ISO timestamp length "2006-01-02T15:04:05")
        var idx = line.startIndex
        var charCount = 0
        while idx < line.endIndex {
            if charCount >= 19, line[idx] == " " {
                return idx
            }
            charCount += 1
            idx = line.index(after: idx)
        }
        return nil
    }
}
