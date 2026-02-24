import MiniDockerCore
import SwiftUI

struct ContainerRowView: View {
    let container: ContainerSummary

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

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

            Text(statusLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        let lower = container.status.lowercased()
        if lower.hasPrefix("up") {
            if container.health == .unhealthy {
                return .orange
            }
            return .green
        }
        return .gray
    }

    private var statusLabel: String {
        let lower = container.status.lowercased()
        if lower.hasPrefix("up") { return "Running" }
        if lower.contains("exited") { return "Exited" }
        if lower.contains("created") { return "Created" }
        if lower.contains("paused") { return "Paused" }
        return container.status
    }
}
