import Foundation

/// Namespace for Docker-specific date parsing utilities.
enum DockerDateParser {
    // MARK: - RFC 3339 with Nanosecond Precision

    /// Parse an RFC 3339 timestamp with optional nanosecond fractional seconds.
    ///
    /// Docker emits timestamps like `"2026-02-22T10:30:00.123456789Z"`.
    /// Foundation only supports millisecond precision, so this function
    /// manually extracts fractional seconds beyond that.
    static func parseRFC3339Nano(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard let dotIndex = trimmed.firstIndex(of: ".") else {
            return parseISO8601Base(trimmed)
        }

        let basePart = String(trimmed[trimmed.startIndex ..< dotIndex])
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]

        var digitChars: [Character] = []
        var suffixStart = afterDot.endIndex
        for (idx, ch) in zip(afterDot.indices, afterDot) {
            if ch.isNumber {
                digitChars.append(ch)
            } else {
                suffixStart = idx
                break
            }
        }

        let suffix = String(afterDot[suffixStart...])
        let padded = String(digitChars).padding(toLength: 9, withPad: "0", startingAt: 0)
        let nanos = Double(String(padded.prefix(9))) ?? 0
        let fractionalSeconds = nanos / 1_000_000_000.0

        let fullBase = basePart + (suffix.isEmpty ? "Z" : suffix)
        guard let date = parseISO8601Base(fullBase) else { return nil }
        return date.addingTimeInterval(fractionalSeconds)
    }

    // MARK: - Unix Nanosecond Epoch

    /// Convert a Unix nanosecond epoch to a `Date`.
    static func parseUnixNano(nanoseconds: Int64) -> Date {
        let seconds = TimeInterval(nanoseconds) / 1_000_000_000.0
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Docker CLI Date Format

    /// Parse the date format from `docker ps --format json` `CreatedAt` field.
    ///
    /// Format: `"2026-02-22 10:30:00 +0000 UTC"`
    static func parseCLIDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Try with UTC suffix first
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z 'UTC'"
        if let date = formatter.date(from: trimmed) { return date }

        // Fallback without UTC suffix
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: trimmed)
    }

    // MARK: - Private

    private static func parseISO8601Base(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
