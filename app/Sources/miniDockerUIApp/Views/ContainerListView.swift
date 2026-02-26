import MiniDockerCore
import SwiftUI

struct ContainerListView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedContainerId) {
            let groups = ContainerGrouper.group(
                containers: viewModel.containers,
                favoriteKeys: viewModel.favoriteKeys,
                keyForContainer: { viewModel.containerKey(for: $0) }
            )
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.containers, id: \.id) { container in
                        ContainerRowView(
                            container: container,
                            isFavorite: viewModel.isFavorite(container),
                            isActionInProgress: viewModel.actionInProgress[container.id] != nil,
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
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadContainers() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
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
}
