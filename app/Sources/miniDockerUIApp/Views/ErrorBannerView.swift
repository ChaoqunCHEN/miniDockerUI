import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var isPersistent: Bool = false
    var onRetry: (() -> Void)?
    let onDismiss: () -> Void

    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer()
            if let onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            guard !isPersistent else { return }
            autoDismissTask = Task {
                do {
                    try await Task.sleep(for: .seconds(8))
                    onDismiss()
                } catch {}
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }
}
