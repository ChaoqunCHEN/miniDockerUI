import MiniDockerCore
import SwiftUI

@main
struct MiniDockerUIApp: App {
    @State private var viewModel: AppViewModel

    init() {
        let settingsPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.miniDockerUI/settings.json")
            .path
        let store = JSONSettingsStore(filePath: settingsPath)
        _viewModel = State(initialValue: AppViewModel(engine: CLIEngineAdapter(), settingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}
