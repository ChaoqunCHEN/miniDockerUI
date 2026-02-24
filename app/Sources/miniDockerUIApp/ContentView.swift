import MiniDockerCore
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            ContainerListView(viewModel: viewModel)
        } detail: {
            if let selectedId = viewModel.selectedContainerId {
                ContainerDetailView(
                    viewModel: ContainerDetailViewModel(
                        engine: viewModel.engine,
                        containerId: selectedId
                    )
                )
                .id(selectedId)
            } else {
                EmptyStateView()
            }
        }
        .task {
            await viewModel.loadContainers()
            viewModel.startEventStream()
        }
    }
}
