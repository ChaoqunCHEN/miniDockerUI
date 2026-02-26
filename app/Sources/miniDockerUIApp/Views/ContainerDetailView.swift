import MiniDockerCore
import SwiftUI

struct ContainerDetailView: View {
    @State var viewModel: ContainerDetailViewModel
    @State private var selectedTab: DetailTab = .logs
    @State private var isSearchVisible: Bool = false

    enum DetailTab: String, CaseIterable {
        case logs = "Logs"
        case readiness = "Readiness"
        case inspect = "Inspect"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let detail = viewModel.detail {
                headerView(detail: detail)
                Divider()
            }

            // Tab bar
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Tab content
            switch selectedTab {
            case .logs:
                EnhancedLogView(detailViewModel: viewModel, isSearchVisible: $isSearchVisible)
            case .readiness:
                ReadinessTrackerView(viewModel: ReadinessViewModel(
                    engine: viewModel.engine,
                    buffer: viewModel.logBuffer,
                    containerId: viewModel.containerId
                ))
            case .inspect:
                ContainerInspectView(viewModel: viewModel)
            }
        }
        // Tab-switching keyboard shortcuts
        .background(
            Group {
                Button("") { selectedTab = .logs }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = .readiness }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .inspect }
                    .keyboardShortcut("3", modifiers: .command)
            }
            .hidden()
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                actionButtons
            }
            ToolbarItem(placement: .destructiveAction) {
                Button {
                    viewModel.clearLogs()
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }
                .help("Clear logs (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
            if selectedTab == .logs {
                ToolbarItem {
                    Button {
                        isSearchVisible.toggle()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .help("Toggle search bar (⌘F)")
                    .keyboardShortcut("f", modifiers: .command)
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .logs {
                isSearchVisible = false
            }
        }
        .task {
            await viewModel.loadDetail()
            viewModel.startLogStream()
        }
        .onDisappear {
            viewModel.stopLogStream()
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                ErrorBannerView(message: error) {
                    viewModel.errorMessage = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func headerView(detail: ContainerDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.summary.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(detail.summary.image)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(for: detail.summary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusBadge(for summary: ContainerSummary) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(summary.statusColor.swiftUIColor)
                .frame(width: 8, height: 8)
            Text(summary.displayStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private var actionButtons: some View {
        let isRunning = viewModel.detail?.summary.isRunning ?? false

        Button {
            Task { await viewModel.startContainer() }
        } label: {
            Label("Start", systemImage: "play.fill")
        }
        .disabled(isRunning)
        .help("Start container")

        Button {
            Task { await viewModel.stopContainer() }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(!isRunning)
        .keyboardShortcut(".", modifiers: .command)
        .help("Stop container (⌘.)")

        Button {
            Task { await viewModel.restartContainer() }
        } label: {
            Label("Restart", systemImage: "arrow.clockwise")
        }
        .disabled(!isRunning)
        .help("Restart container")
    }
}
