import SwiftUI
import MiniDockerCore

@main
struct MiniDockerUIApp: App {
    @State private var status: String = MiniDockerCore.preflightSummary()

    var body: some Scene {
        WindowGroup {
            ContentView(status: $status)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}
