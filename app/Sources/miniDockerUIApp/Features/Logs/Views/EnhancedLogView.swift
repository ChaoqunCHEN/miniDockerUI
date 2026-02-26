import MiniDockerCore
import SwiftUI

struct EnhancedLogView: View {
    let detailViewModel: ContainerDetailViewModel
    @Binding var isSearchVisible: Bool
    @State private var searchViewModel: LogSearchViewModel

    init(detailViewModel: ContainerDetailViewModel, isSearchVisible: Binding<Bool>) {
        self.detailViewModel = detailViewModel
        _isSearchVisible = isSearchVisible
        _searchViewModel = State(initialValue: LogSearchViewModel(
            buffer: detailViewModel.logBuffer,
            containerId: detailViewModel.containerId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                LogSearchBarView(viewModel: searchViewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            logContent

            Divider()
            statusBar
        }
        .animation(.easeInOut(duration: 0.15), value: isSearchVisible)
        .onChange(of: isSearchVisible) { _, visible in
            if !visible {
                searchViewModel.clearSearch()
            }
        }
    }

    // MARK: - Log Content

    private var logContent: some View {
        SelectableLogTextView(
            displayEntries: detailViewModel.displayEntries,
            searchResults: searchViewModel.results,
            selectedResultIndex: searchViewModel.selectedResultIndex,
            onMatchSelected: { matchIndex in
                searchViewModel.selectedResultIndex = matchIndex
            }
        )
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
