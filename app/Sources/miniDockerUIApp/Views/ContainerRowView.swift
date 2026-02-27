import MiniDockerCore
import SwiftUI

struct ContainerRowView: View {
    let container: ContainerSummary
    var isFavorite: Bool = false
    var isActionInProgress: Bool = false
    var readinessDisplay: String? = nil
    var onToggleFavorite: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if isActionInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Show star only when hovered or already favorited — reduces noise at rest
            if let onToggleFavorite, isFavorite || isHovered {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onHover { isHovered = $0 }
        .help(statusTooltip)
    }

    // MARK: - Status Text

    private var statusText: String {
        if let readinessDisplay { return readinessDisplay }
        if container.isRunning { return "-" }
        return container.displayStatus
    }

    // MARK: - Status Dot Color

    private var statusDotColor: Color {
        if let display = readinessDisplay, container.isRunning {
            return display == "Ready" ? .green : .orange
        }
        return container.statusColor.swiftUIColor
    }

    // MARK: - Tooltip

    private var statusTooltip: String {
        guard let display = readinessDisplay else {
            return container.displayStatus
        }
        return display == "Ready" ? "Container ready" : "Evaluating readiness..."
    }
}

// MARK: - ContainerStatusColor SwiftUI Extension

extension ContainerStatusColor {
    var swiftUIColor: Color {
        switch self {
        case .running: .green
        case .warning: .orange
        case .stopped: .gray
        }
    }
}
