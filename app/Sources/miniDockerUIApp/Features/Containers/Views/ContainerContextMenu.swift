import MiniDockerCore
import SwiftUI

struct ContainerContextMenu: View {
    let container: ContainerSummary
    let isFavorite: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onToggleFavorite) {
            Label(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }

        Divider()

        Button(action: onStart) {
            Label("Start", systemImage: "play.fill")
        }
        .disabled(container.isRunning)

        Button(action: onStop) {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(!container.isRunning)

        Button(action: onRestart) {
            Label("Restart", systemImage: "arrow.clockwise")
        }
        .disabled(!container.isRunning)
    }
}
