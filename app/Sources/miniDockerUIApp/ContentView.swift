import MiniDockerCore
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            ContainerListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let selectedId = viewModel.selectedContainerId {
                ContainerDetailView(
                    viewModel: ContainerDetailViewModel(
                        engine: viewModel.engine,
                        containerId: selectedId,
                        logBuffer: viewModel.logBuffer
                    )
                )
                .id(selectedId)
            } else {
                EmptyStateView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = viewModel.errorMessage {
                ErrorBannerView(message: error) {
                    viewModel.errorMessage = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
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
