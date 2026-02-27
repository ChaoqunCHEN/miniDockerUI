import MiniDockerCore
import SwiftUI

struct ContainerListView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedContainerId) {
            ForEach(containerGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.containers, id: \.id) { container in
                        containerRow(for: container)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                WorktreePickerView(viewModel: viewModel.worktreeViewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refreshAndReconnect() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh container list")
            }
        }
        .overlay {
            if viewModel.containers.isEmpty, !viewModel.isLoading {
                ContentUnavailableView(
                    "No Containers",
                    systemImage: "shippingbox",
                    description: Text("No Docker containers found.")
                )
            }
        }
    }

    private var containerGroups: [ContainerGroup] {
        ContainerGrouper.group(
            containers: viewModel.containers,
            favoriteKeys: viewModel.favoriteKeys,
            keyForContainer: { viewModel.containerKey(for: $0) }
        )
    }

    private func containerRow(for container: ContainerSummary) -> some View {
        ContainerRowView(
            container: container,
            isFavorite: viewModel.isFavorite(container),
            isActionInProgress: viewModel.actionInProgress[container.id] != nil,
            readinessDisplay: viewModel.readinessManager.readinessDisplay(for: container),
            onToggleFavorite: { viewModel.toggleFavorite(for: container) }
        )
        .tag(container.id)
        .contextMenu {
            ContainerContextMenu(
                container: container,
                isFavorite: viewModel.isFavorite(container),
                onStart: { Task { await viewModel.startContainer(id: container.id) } },
                onStop: { Task { await viewModel.stopContainer(id: container.id) } },
                onRestart: { Task { await viewModel.restartContainer(id: container.id) } },
                onToggleFavorite: { viewModel.toggleFavorite(for: container) }
            )
        }
    }
}
