import MiniDockerCore
import SwiftUI

struct ContainerLogView: View {
    let viewModel: ContainerDetailViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(viewModel.displayEntries.enumerated()), id: \.offset) { index, entry in
                        logEntryRow(entry: entry)
                            .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.displayEntries.count) { _, newCount in
                if newCount > 0 {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                if viewModel.isStreamingLogs {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2)
                }
                Text("\(viewModel.displayEntries.count) lines")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .padding(8)
        }
    }

    private func logEntryRow(entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTimestamp(entry.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.stream == .stderr ? .red : .primary)
                .textSelection(.enabled)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }
}
