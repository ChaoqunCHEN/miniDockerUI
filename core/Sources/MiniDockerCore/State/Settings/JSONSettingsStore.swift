import Foundation

/// Concrete `AppSettingsStore` backed by a JSON file on disk.
///
/// Reads and writes `AppSettings` as pretty-printed, sorted-keys JSON.
/// When the file does not exist, `load()` returns `AppSettings.defaultSettings`.
public struct JSONSettingsStore: AppSettingsStore, Sendable {
    public let filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }

    public func load() throws -> AppSettingsSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            return AppSettings.defaultSettings
        }

        let url = URL(fileURLWithPath: filePath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CoreError.fileReadFailed(
                path: filePath,
                reason: error.localizedDescription
            )
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AppSettingsSnapshot.self, from: data)
        } catch {
            throw CoreError.decodingFailed(
                context: "JSONSettingsStore.load",
                reason: error.localizedDescription
            )
        }
    }

    public func save(_ snapshot: AppSettingsSnapshot) throws {
        let url = URL(fileURLWithPath: filePath)
        let parentDirectory = url.deletingLastPathComponent()

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: parentDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw CoreError.directoryCreateFailed(
                    path: parentDirectory.path,
                    reason: error.localizedDescription
                )
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw CoreError.encodingFailed(
                context: "JSONSettingsStore.save",
                reason: error.localizedDescription
            )
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CoreError.fileWriteFailed(
                path: filePath,
                reason: error.localizedDescription
            )
        }
    }
}

// MARK: - AppSettings Defaults

public extension AppSettings {
    /// The current schema version used by new settings files.
    static let currentSchemaVersion = SchemaVersion(major: 1, minor: 0, patch: 0)

    /// Default settings for a fresh installation.
    static let defaultSettings = AppSettings(
        schemaVersion: currentSchemaVersion.description,
        favoriteContainerKeys: [],
        actionPreferences: [:],
        worktreeMappings: [],
        readinessRules: [:],
        transientUIPreferences: [:]
    )
}
