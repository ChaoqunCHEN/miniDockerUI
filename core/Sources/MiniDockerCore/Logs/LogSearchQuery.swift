import Foundation

/// Describes a search over log entries in a ``LogRingBuffer``.
public struct LogSearchQuery: Sendable, Equatable {
    /// How the pattern should be matched against log messages.
    public enum MatchMode: String, Sendable, Codable, Equatable {
        case substring
        case regex
        case exact
    }

    public let pattern: String
    public let matchMode: MatchMode
    public let caseSensitive: Bool
    public let streamFilter: Set<LogStream>?
    public let containerFilter: String?
    public let fromDate: Date?
    public let toDate: Date?
    public let maxResults: Int?

    public init(
        pattern: String,
        matchMode: MatchMode = .substring,
        caseSensitive: Bool = false,
        streamFilter: Set<LogStream>? = nil,
        containerFilter: String? = nil,
        fromDate: Date? = nil,
        toDate: Date? = nil,
        maxResults: Int? = nil
    ) {
        self.pattern = pattern
        self.matchMode = matchMode
        self.caseSensitive = caseSensitive
        self.streamFilter = streamFilter
        self.containerFilter = containerFilter
        self.fromDate = fromDate
        self.toDate = toDate
        self.maxResults = maxResults
    }
}

/// A single search result with the matching entry and highlight ranges.
public struct LogSearchResult: Sendable, Equatable {
    public let entry: LogEntry
    public let matchRanges: [Range<String.Index>]

    public init(entry: LogEntry, matchRanges: [Range<String.Index>]) {
        self.entry = entry
        self.matchRanges = matchRanges
    }
}
