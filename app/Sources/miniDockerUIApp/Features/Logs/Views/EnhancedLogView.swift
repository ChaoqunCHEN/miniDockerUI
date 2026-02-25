import MiniDockerCore
import SwiftUI

struct EnhancedLogView: View {
    let detailViewModel: ContainerDetailViewModel
    @State private var searchViewModel: LogSearchViewModel
    @State private var isSearchVisible: Bool = false

    init(detailViewModel: ContainerDetailViewModel) {
        self.detailViewModel = detailViewModel
        _searchViewModel = State(initialValue: LogSearchViewModel(
            buffer: detailViewModel.logBuffer,
            containerId: detailViewModel.containerId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                LogSearchBarView(viewModel: searchViewModel)
                Divider()
            }

            logContent

            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isSearchVisible.toggle()
                    if !isSearchVisible {
                        searchViewModel.clearSearch()
                    }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Toggle search bar")
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(
                        Array(detailViewModel.displayEntries.enumerated()),
                        id: \.offset
                    ) { index, entry in
                        logEntryRow(entry: entry, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: detailViewModel.displayEntries.count) { _, newCount in
                if newCount > 0, searchViewModel.results.isEmpty {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
            .onChange(of: searchViewModel.selectedResultIndex) { _, newIndex in
                guard let newIndex,
                      newIndex < searchViewModel.results.count
                else { return }
                let selectedEntry = searchViewModel.results[newIndex].entry
                if let entryIndex = detailViewModel.displayEntries.firstIndex(where: {
                    $0.timestamp == selectedEntry.timestamp && $0.message == selectedEntry.message
                }) {
                    withAnimation {
                        proxy.scrollTo(entryIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Log Entry Row

    private func logEntryRow(entry: LogEntry, index _: Int) -> some View {
        let isHighlighted = isEntryHighlighted(entry)

        return HStack(alignment: .top, spacing: 8) {
            Text(formatTimestamp(entry.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.stream == .stderr ? .red : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .background(isHighlighted ? Color.yellow.opacity(0.2) : Color.clear)
    }

    private func isEntryHighlighted(_ entry: LogEntry) -> Bool {
        guard let selectedIndex = searchViewModel.selectedResultIndex,
              selectedIndex < searchViewModel.results.count
        else { return false }
        let selectedEntry = searchViewModel.results[selectedIndex].entry
        return entry.timestamp == selectedEntry.timestamp && entry.message == selectedEntry.message
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if detailViewModel.isStreamingLogs {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2)
                }
            }

            Spacer()

            Text(lineCountText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(byteSizeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var lineCountText: String {
        let count = detailViewModel.logBuffer.lineCount(forContainer: detailViewModel.containerId)
        return "\(count) lines"
    }

    private var byteSizeText: String {
        let bytes = detailViewModel.logBuffer.byteCount(forContainer: detailViewModel.containerId)
        return formatBytes(bytes)
    }

    // MARK: - Formatting

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}
