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
                    viewModel: viewModel.detailViewModel(for: selectedId)
                )
                .id(selectedId)
            } else {
                EmptyStateView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = viewModel.currentError {
                errorBanner(for: error)
            }
        }
        .task {
            await viewModel.refreshAndReconnect()
        }
        .onDisappear {
            viewModel.stopEventStream()
        }
    }

    private func errorBanner(for error: AppError) -> some View {
        ErrorBannerView(
            message: error.message,
            isPersistent: error.isPersistent,
            onRetry: error.isPersistent
                ? { Task { await viewModel.refreshAndReconnect() } }
                : nil,
            onDismiss: { viewModel.currentError = nil }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentError)
    }
}
