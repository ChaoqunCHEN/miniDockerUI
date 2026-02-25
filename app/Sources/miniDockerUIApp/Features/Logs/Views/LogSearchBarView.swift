import MiniDockerCore
import SwiftUI

struct LogSearchBarView: View {
    @Bindable var viewModel: LogSearchViewModel

    var body: some View {
        HStack(spacing: 8) {
            searchField
            matchModePicker
            caseSensitiveToggle
            resultCountLabel
            navigationButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search logs...", text: $viewModel.queryText)
                .textFieldStyle(.plain)
                .onSubmit { viewModel.search() }
            if !viewModel.queryText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 200)
    }

    private var matchModePicker: some View {
        Picker("Mode", selection: $viewModel.matchMode) {
            Text("Text").tag(LogSearchQuery.MatchMode.substring)
            Text("Regex").tag(LogSearchQuery.MatchMode.regex)
            Text("Exact").tag(LogSearchQuery.MatchMode.exact)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    private var caseSensitiveToggle: some View {
        Toggle(isOn: $viewModel.caseSensitive) {
            Text("Aa")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .toggleStyle(.button)
        .help("Case sensitive")
    }

    private var resultCountLabel: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !viewModel.queryText.isEmpty {
                Text("\(viewModel.resultCount) match\(viewModel.resultCount == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.selectPreviousResult()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(viewModel.results.isEmpty)

            Button {
                viewModel.selectNextResult()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(viewModel.results.isEmpty)
        }
        .buttonStyle(.borderless)
    }
}
