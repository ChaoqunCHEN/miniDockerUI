import MiniDockerCore
import SwiftUI

struct ContainerDetailView: View {
    @State var viewModel: ContainerDetailViewModel
    @State private var selectedTab: DetailTab = .logs

    enum DetailTab: String, CaseIterable {
        case logs = "Logs"
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

            // Tab content
            switch selectedTab {
            case .logs:
                ContainerLogView(viewModel: viewModel)
            case .inspect:
                ContainerInspectView(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                actionButtons
            }
        }
        .task {
            await viewModel.loadDetail()
            viewModel.startLogStream()
        }
        .onDisappear {
            viewModel.stopLogStream()
        }
        .overlay {
            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding()
                }
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
            statusBadge(status: detail.summary.status, health: detail.summary.health)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusBadge(status: String, health _: ContainerHealthStatus?) -> some View {
        let isRunning = status.lowercased().hasPrefix("up")
        HStack(spacing: 4) {
            Circle()
                .fill(isRunning ? .green : .gray)
                .frame(width: 8, height: 8)
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private var actionButtons: some View {
        let isRunning = viewModel.detail?.summary.status.lowercased().hasPrefix("up") ?? false

        Button {
            Task { await viewModel.startContainer() }
        } label: {
            Label("Start", systemImage: "play.fill")
        }
        .disabled(isRunning)

        Button {
            Task { await viewModel.stopContainer() }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(!isRunning)

        Button {
            Task { await viewModel.restartContainer() }
        } label: {
            Label("Restart", systemImage: "arrow.clockwise")
        }
        .disabled(!isRunning)
    }
}
