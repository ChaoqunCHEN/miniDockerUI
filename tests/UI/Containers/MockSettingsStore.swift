import Foundation
import MiniDockerCore

final class MockSettingsStore: AppSettingsStore, @unchecked Sendable {
    var settings: AppSettingsSnapshot = AppSettings.defaultSettings
    var loadCallCount = 0
    var saveCallCount = 0
    var shouldThrowOnLoad = false
    var shouldThrowOnSave = false

    func load() throws -> AppSettingsSnapshot {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw CoreError.fileReadFailed(path: "mock", reason: "mock error")
        }
        return settings
    }

    func save(_ snapshot: AppSettingsSnapshot) throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw CoreError.fileWriteFailed(path: "mock", reason: "mock error")
        }
        settings = snapshot
    }
}
