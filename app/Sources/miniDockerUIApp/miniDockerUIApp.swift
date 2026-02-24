import MiniDockerCore
import SwiftUI

@main
struct MiniDockerUIApp: App {
    @State private var viewModel = AppViewModel(engine: CLIEngineAdapter())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}
