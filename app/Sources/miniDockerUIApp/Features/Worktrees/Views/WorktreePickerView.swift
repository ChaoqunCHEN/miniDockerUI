import MiniDockerCore
import SwiftUI

/// Toolbar dropdown for selecting git worktrees per compose project.
///
/// Always visible in the sidebar toolbar. Shows detected compose projects
/// and their available git worktrees. Selecting a different worktree is
/// a UI-only action — the actual Docker recreation happens when the user
/// clicks Restart on a container.
struct WorktreePickerView: View {
    @Bindable var viewModel: ComposeWorktreeViewModel

    var body: some View {
        Menu {
            if viewModel.detectedProjects.isEmpty {
                Text("No compose projects detected")
            } else {
                ForEach(viewModel.detectedProjects, id: \.projectName) { project in
                    projectSection(project)
                }
            }
        } label: {
            Label("Worktrees", systemImage: "arrow.triangle.branch")
                .overlay(alignment: .topTrailing) {
                    if viewModel.hasPendingChanges {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .help("Select git worktree for compose projects")
    }

    @ViewBuilder
    private func projectSection(_ project: ComposeProject) -> some View {
        let worktrees = (viewModel.projectWorktrees[project.projectName] ?? [])
            .filter { !$0.isBare }
        let currentDir = project.workingDirectory
        let selectedDir = viewModel.selectedWorktrees[project.projectName] ?? currentDir

        Section(project.projectName) {
            ForEach(worktrees, id: \.path) { worktree in
                let isSelected = worktree.path == selectedDir
                let label = worktree.shortBranch ?? worktree.path
                Button {
                    viewModel.selectedWorktrees[project.projectName] = worktree.path
                } label: {
                    HStack {
                        Text(label)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }
}
