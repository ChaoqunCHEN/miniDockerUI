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
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                ErrorBannerView(message: error) {
                    viewModel.errorMessage = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.loadContainers()
            viewModel.startEventStream()
        }
        .onDisappear {
            viewModel.stopEventStream()
        }
    }
}
