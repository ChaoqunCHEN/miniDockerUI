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
            throw CoreError.outputParseFailure(
                context: "JSONSettingsStore.load",
                rawSnippet: "Failed to read file at \(filePath): \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AppSettingsSnapshot.self, from: data)
        } catch {
            throw CoreError.outputParseFailure(
                context: "JSONSettingsStore.load",
                rawSnippet: String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
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
                throw CoreError.outputParseFailure(
                    context: "JSONSettingsStore.save",
                    rawSnippet: "Failed to create directory \(parentDirectory.path): \(error.localizedDescription)"
                )
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw CoreError.outputParseFailure(
                context: "JSONSettingsStore.save",
                rawSnippet: "Failed to encode settings: \(error.localizedDescription)"
            )
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CoreError.outputParseFailure(
                context: "JSONSettingsStore.save",
                rawSnippet: "Failed to write file at \(filePath): \(error.localizedDescription)"
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
