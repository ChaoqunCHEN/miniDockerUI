import MiniDockerCore
import SwiftUI

struct WorktreeSwitchView: View {
    @Bindable var viewModel: WorktreeSwitchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mappingsSection
                    switchFormSection
                    planPreviewSection
                    progressSection
                }
                .padding(16)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { viewModel.loadMappings() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Worktree Switch")
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Mappings List

    private var mappingsSection: some View {
        GroupBox("Mappings") {
            if viewModel.mappings.isEmpty {
                Text("No worktree mappings configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.mappings, id: \.id) { mapping in
                        WorktreeMappingRow(
                            mapping: mapping,
                            isSelected: viewModel.selectedMappingId == mapping.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedMappingId = mapping.id
                        }
                    }
                }
            }
        }
    }

    // MARK: - Switch Form

    private var switchFormSection: some View {
        GroupBox("Switch Configuration") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("From worktree path", text: $viewModel.fromWorktree)
                    .textFieldStyle(.roundedBorder)

                TextField("To worktree path", text: $viewModel.toWorktree)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Plan Switch") {
                        Task { await viewModel.planSwitch() }
                    }
                    .disabled(viewModel.selectedMappingId == nil
                        || viewModel.fromWorktree.isEmpty
                        || viewModel.toWorktree.isEmpty)

                    if viewModel.switchPlan != nil {
                        Button("Execute Switch") {
                            Task { await viewModel.executeSwitch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSwitching)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Plan Preview

    @ViewBuilder
    private var planPreviewSection: some View {
        if let plan = viewModel.switchPlan {
            GroupBox("Switch Plan") {
                VStack(alignment: .leading, spacing: 6) {
                    planRow(label: "Mapping", value: plan.mappingId)
                    planRow(label: "From", value: plan.fromWorktree)
                    planRow(label: "To", value: plan.toWorktree)
                    planRow(
                        label: "Restart Targets",
                        value: plan.restartTargets.isEmpty
                            ? "None"
                            : plan.restartTargets.joined(separator: ", ")
                    )
                    planRow(label: "Verify Mode", value: plan.verifyRule.mode.rawValue)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func planRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if viewModel.switchProgress != .idle {
            GroupBox("Progress") {
                HStack(spacing: 8) {
                    progressIcon
                    Text(progressMessage)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var progressIcon: some View {
        switch viewModel.switchProgress {
        case .idle:
            EmptyView()
        case .planning, .restarting, .verifyingReadiness:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var progressMessage: String {
        switch viewModel.switchProgress {
        case .idle:
            return ""
        case .planning:
            return "Planning switch..."
        case let .restarting(containerId):
            return "Restarting \(containerId)..."
        case .verifyingReadiness:
            return "Verifying readiness..."
        case .completed:
            return "Switch completed successfully."
        case let .failed(reason):
            return "Switch failed: \(reason)"
        }
    }
}
