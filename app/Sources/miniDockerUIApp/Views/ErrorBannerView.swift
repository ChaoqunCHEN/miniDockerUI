import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button {
                onDismiss()
            } label: {
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
            autoDismissTask = Task {
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled {
                    onDismiss()
                }
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }
}
