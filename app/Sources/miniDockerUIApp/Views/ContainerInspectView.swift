import MiniDockerCore
import SwiftUI

struct ContainerInspectView: View {
    let viewModel: ContainerDetailViewModel

    var body: some View {
        if let detail = viewModel.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection(detail: detail)
                    networkSection(detail: detail)
                    mountsSection(detail: detail)
                    if let health = detail.healthDetail {
                        healthSection(health: health)
                    }
                }
                .padding(16)
            }
        } else if viewModel.isLoadingDetail {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Details",
                systemImage: "doc.questionmark",
                description: Text("Unable to load container details.")
            )
        }
    }

    // MARK: - Sections

    private func summarySection(detail: ContainerDetail) -> some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow(label: "ID", value: String(detail.summary.id.prefix(12)))
                infoRow(label: "Image", value: detail.summary.image)
                infoRow(label: "Status", value: detail.summary.status)
                if let startedAt = detail.summary.startedAt {
                    infoRow(label: "Started", value: formatDate(startedAt))
                }
                if !detail.summary.labels.isEmpty {
                    HStack(alignment: .top) {
                        Text("Labels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(
                                Array(detail.summary.labels.sorted(by: { $0.key < $1.key })),
                                id: \.key
                            ) { key, value in
                                Text("\(key) = \(value)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func networkSection(detail: ContainerDetail) -> some View {
        let net = detail.networkSettings
        GroupBox("Network") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow(label: "Mode", value: net.networkMode)
                if !net.ipAddressesByNetwork.isEmpty {
                    ForEach(Array(net.ipAddressesByNetwork), id: \.key) { network, ip in
                        infoRow(label: network, value: ip)
                    }
                }
                if !net.ports.isEmpty {
                    ForEach(Array(net.ports.enumerated()), id: \.offset) { _, port in
                        let hostDisplay = port.hostPort.map { ":\($0)" } ?? ""
                        let hostIP = port.hostIP ?? ""
                        infoRow(
                            label: port.containerPort,
                            value: "\(hostIP)\(hostDisplay)"
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mountsSection(detail: ContainerDetail) -> some View {
        if !detail.mounts.isEmpty {
            GroupBox("Mounts") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(detail.mounts.enumerated()), id: \.offset) { _, mount in
                        HStack(alignment: .top) {
                            Text(mount.source)
                                .font(.system(size: 11, design: .monospaced))
                            Text("→")
                                .foregroundStyle(.secondary)
                            Text(mount.destination)
                                .font(.system(size: 11, design: .monospaced))
                            if mount.isReadOnly {
                                Text("(ro)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func healthSection(health: ContainerHealthDetail) -> some View {
        GroupBox("Health") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow(label: "Status", value: health.status.rawValue)
                infoRow(label: "Failing Streak", value: String(health.failingStreak))
                if !health.logs.isEmpty {
                    Text("Recent Checks")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)
                    ForEach(Array(health.logs.suffix(3).enumerated()), id: \.offset) { _, log in
                        HStack {
                            Text("Exit \(log.exitCode)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(log.exitCode == 0 ? .green : .red)
                            Text(log.output.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
