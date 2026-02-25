import MiniDockerCore
import SwiftUI

struct ReadinessTrackerView: View {
    @Bindable var viewModel: ReadinessViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                ruleConfigurationSection
                evaluationDetailsSection
            }
            .padding(16)
        }
        .task {
            await viewModel.evaluate()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GroupBox("Readiness Status") {
            HStack {
                readinessBadge
                Spacer()
                if viewModel.isEvaluating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Evaluate") {
                    Task { await viewModel.evaluate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isEvaluating)
            }
            .padding(.vertical, 4)
        }
    }

    private var readinessBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(readinessColor)
                .frame(width: 10, height: 10)
            Text(readinessLabel)
                .font(.headline)
        }
    }

    private var readinessColor: Color {
        guard let result = viewModel.result else { return .gray }
        return result.isReady ? .green : .red
    }

    private var readinessLabel: String {
        guard let result = viewModel.result else { return "Not Evaluated" }
        return result.isReady ? "Ready" : "Not Ready"
    }

    // MARK: - Rule Configuration

    private var ruleConfigurationSection: some View {
        GroupBox("Rule Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                if viewModel.editingMode == .regexOnly
                    || viewModel.editingMode == .healthThenRegex
                {
                    regexFields
                }
                windowPolicyPicker
            }
            .padding(.vertical, 4)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.editingMode) {
            ForEach(ReadinessMode.allCases, id: \.self) { mode in
                Text(displayName(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var regexFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Regex pattern", text: $viewModel.editingRegexPattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Stepper("Match count: \(viewModel.editingMustMatchCount)",
                    value: $viewModel.editingMustMatchCount,
                    in: 1 ... 100)
        }
    }

    private var windowPolicyPicker: some View {
        Picker("Window Start", selection: $viewModel.editingWindowStartPolicy) {
            ForEach(ReadinessWindowStartPolicy.allCases, id: \.self) { policy in
                Text(displayName(for: policy)).tag(policy)
            }
        }
    }

    // MARK: - Evaluation Details

    private var evaluationDetailsSection: some View {
        GroupBox("Evaluation Details") {
            if let result = viewModel.result {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(label: "Health Satisfied", value: result.healthSatisfied ? "Yes" : "No")
                    detailRow(label: "Regex Matches", value: "\(result.regexMatchCount)")
                    detailRow(label: "Evaluated Entries", value: "\(result.evaluatedEntries)")
                    detailRow(label: "Rejected Stale", value: "\(result.rejectedStaleEntries)")
                }
                .padding(.vertical, 4)
            } else {
                Text("No evaluation results yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Display Names

    private func displayName(for mode: ReadinessMode) -> String {
        switch mode {
        case .healthOnly: return "Health Only"
        case .healthThenRegex: return "Health + Regex"
        case .regexOnly: return "Regex Only"
        }
    }

    private func displayName(for policy: ReadinessWindowStartPolicy) -> String {
        switch policy {
        case .containerStart: return "Container Start"
        case .actionDispatch: return "Action Dispatch"
        case .firstLogEntry: return "First Log Entry"
        }
    }
}
