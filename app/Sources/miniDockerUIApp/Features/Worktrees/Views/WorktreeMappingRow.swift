import MiniDockerCore
import SwiftUI

struct WorktreeMappingRow: View {
    let mapping: WorktreeMapping
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.id)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(mapping.targetType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mapping.targetId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            restartPolicyBadge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var restartPolicyBadge: some View {
        Text(mapping.restartPolicy.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(restartPolicyColor.opacity(0.15))
            .foregroundStyle(restartPolicyColor)
            .clipShape(Capsule())
    }

    private var restartPolicyColor: Color {
        switch mapping.restartPolicy {
        case .never: return .gray
        case .ifRunning: return .orange
        case .always: return .blue
        }
    }
}
