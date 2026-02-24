import MiniDockerCore
import SwiftUI

struct ContainerListView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedContainerId) {
            if !runningContainers.isEmpty {
                Section("Running") {
                    ForEach(runningContainers, id: \.id) { container in
                        ContainerRowView(container: container)
                            .tag(container.id)
                    }
                }
            }
            if !stoppedContainers.isEmpty {
                Section("Stopped") {
                    ForEach(stoppedContainers, id: \.id) { container in
                        ContainerRowView(container: container)
                            .tag(container.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.loadContainers() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
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

    private var runningContainers: [ContainerSummary] {
        viewModel.containers
            .filter { $0.status.lowercased().hasPrefix("up") }
            .sorted { $0.name < $1.name }
    }

    private var stoppedContainers: [ContainerSummary] {
        viewModel.containers
            .filter { !$0.status.lowercased().hasPrefix("up") }
            .sorted { $0.name < $1.name }
    }
}
