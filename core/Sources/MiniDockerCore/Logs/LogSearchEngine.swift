import Foundation

/// Provides search primitives over a ``LogRingBuffer``.
public struct LogSearchEngine: Sendable {
    public init() {}

    /// Search entries matching the query, ordered by timestamp (oldest first).
    public func search(in buffer: LogRingBuffer, query: LogSearchQuery) -> [LogSearchResult] {
        let candidates = gatherCandidates(from: buffer, query: query)
        var results: [LogSearchResult] = []

        for entry in candidates {
            let ranges = findMatches(in: entry.message, query: query)
            if !ranges.isEmpty {
                results.append(LogSearchResult(entry: entry, matchRanges: ranges))
                if let max = query.maxResults, results.count >= max {
                    break
                }
            }
        }

        return results
    }

    /// Count matching entries without materializing full results.
    public func count(in buffer: LogRingBuffer, query: LogSearchQuery) -> Int {
        let candidates = gatherCandidates(from: buffer, query: query)
        var count = 0
        for entry in candidates {
            if !findMatches(in: entry.message, query: query).isEmpty {
                count += 1
            }
        }
        return count
    }

    // MARK: - Private

    private func gatherCandidates(from buffer: LogRingBuffer, query: LogSearchQuery) -> [LogEntry] {
        if let cid = query.containerFilter {
            let entries = buffer.entries(forContainer: cid, from: query.fromDate, to: query.toDate)
            return applyStreamFilter(entries, filter: query.streamFilter)
        }

        // No container filter: gather from all containers, merged by timestamp.
        var all: [LogEntry] = []
        for cid in buffer.containerIds {
            let entries = buffer.entries(forContainer: cid, from: query.fromDate, to: query.toDate)
            all.append(contentsOf: applyStreamFilter(entries, filter: query.streamFilter))
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    private func applyStreamFilter(_ entries: [LogEntry], filter: Set<LogStream>?) -> [LogEntry] {
        guard let filter else { return entries }
        return entries.filter { filter.contains($0.stream) }
    }

    private func findMatches(in message: String, query: LogSearchQuery) -> [Range<String.Index>] {
        switch query.matchMode {
        case .exact:
            if query.caseSensitive {
                return message == query.pattern
                    ? [message.startIndex ..< message.endIndex]
                    : []
            } else {
                return message.lowercased() == query.pattern.lowercased()
                    ? [message.startIndex ..< message.endIndex]
                    : []
            }

        case .substring:
            let options: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
            var ranges: [Range<String.Index>] = []
            var searchStart = message.startIndex
            while searchStart < message.endIndex,
                  let range = message.range(of: query.pattern, options: options, range: searchStart ..< message.endIndex)
            {
                ranges.append(range)
                searchStart = range.upperBound
            }
            return ranges

        case .regex:
            let options: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: query.pattern, options: options) else {
                return []
            }
            let nsRange = NSRange(message.startIndex ..< message.endIndex, in: message)
            let matches = regex.matches(in: message, range: nsRange)
            return matches.compactMap { match in
                Range(match.range, in: message)
            }
        }
    }
}
