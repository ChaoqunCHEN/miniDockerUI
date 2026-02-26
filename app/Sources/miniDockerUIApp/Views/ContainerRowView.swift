import MiniDockerCore
import SwiftUI

struct ContainerRowView: View {
    let container: ContainerSummary
    var isFavorite: Bool = false
    var isActionInProgress: Bool = false
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
                    .fill(container.statusColor.swiftUIColor)
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

            Text(container.displayStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onHover { isHovered = $0 }
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
