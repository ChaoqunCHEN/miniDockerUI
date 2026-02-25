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
        let policy = LogBufferPolicy(
            maxLinesPerContainer: 100_000,
            maxBytesPerContainer: 10 * 1024 * 1024,
            dropStrategy: .dropOldest,
            flushHz: 30
        )
        let logBuffer = LogRingBuffer(policy: policy)
        _viewModel = State(initialValue: AppViewModel(
            engine: CLIEngineAdapter(),
            settingsStore: store,
            logBuffer: logBuffer
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}
