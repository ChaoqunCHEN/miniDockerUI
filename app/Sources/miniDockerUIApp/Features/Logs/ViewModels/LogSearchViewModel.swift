import MiniDockerCore
import Observation

@MainActor
@Observable
final class LogSearchViewModel {
    private let searchEngine: LogSearchEngine
    private let buffer: LogRingBuffer
    let containerId: String

    var queryText: String = ""
    var matchMode: LogSearchQuery.MatchMode = .substring
    var caseSensitive: Bool = false
    var streamFilter: Set<LogStream>?
    var isSearching: Bool = false
    var results: [LogSearchResult] = []
    var resultCount: Int {
        results.count
    }

    var selectedResultIndex: Int?
    var errorMessage: String?

    init(
        buffer: LogRingBuffer,
        containerId: String,
        searchEngine: LogSearchEngine = LogSearchEngine()
    ) {
        self.buffer = buffer
        self.containerId = containerId
        self.searchEngine = searchEngine
    }

    // MARK: - Search

    func search() {
        guard !queryText.isEmpty else {
            clearSearch()
            return
        }

        isSearching = true
        errorMessage = nil

        let query = LogSearchQuery(
            pattern: queryText,
            matchMode: matchMode,
            caseSensitive: caseSensitive,
            streamFilter: streamFilter,
            containerFilter: containerId
        )

        results = searchEngine.search(in: buffer, query: query)
        isSearching = false

        if !results.isEmpty {
            selectedResultIndex = 0
        } else {
            selectedResultIndex = nil
        }
    }

    func clearSearch() {
        queryText = ""
        results = []
        selectedResultIndex = nil
        errorMessage = nil
        isSearching = false
    }

    // MARK: - Result Navigation

    func selectNextResult() {
        guard !results.isEmpty else { return }
        if let current = selectedResultIndex {
            selectedResultIndex = (current + 1) % results.count
        } else {
            selectedResultIndex = 0
        }
    }

    func selectPreviousResult() {
        guard !results.isEmpty else { return }
        if let current = selectedResultIndex {
            selectedResultIndex = (current - 1 + results.count) % results.count
        } else {
            selectedResultIndex = results.count - 1
        }
    }
}
