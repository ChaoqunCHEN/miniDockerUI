@testable import MiniDockerCore
import XCTest

final class JSONSettingsStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        let uniqueDir = "JSONSettingsStoreTests-\(UUID().uuidString)"
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueDir)
    }

    override func tearDown() {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    // MARK: - Tests

    func testSaveAndLoadRoundTrip() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let filePath = tempDirectory.appendingPathComponent("settings.json").path
        let store = JSONSettingsStore(filePath: filePath)

        let settings = AppSettings.defaultSettings
        try store.save(settings)

        let loaded = try store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testLoadReturnsDefaultsWhenFileNotFound() throws {
        let filePath = "/tmp/nonexistent-\(UUID().uuidString)/settings.json"
        let store = JSONSettingsStore(filePath: filePath)

        let loaded = try store.load()
        XCTAssertEqual(loaded, AppSettings.defaultSettings)
    }

    func testLoadThrowsOnCorruptJSON() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let filePath = tempDirectory.appendingPathComponent("settings.json").path

        // Write garbage data to the file.
        try Data("not valid json {{{".utf8).write(to: URL(fileURLWithPath: filePath))

        let store = JSONSettingsStore(filePath: filePath)
        XCTAssertThrowsError(try store.load()) { error in
            guard case CoreError.outputParseFailure = error else {
                XCTFail("Expected CoreError.outputParseFailure, got \(error)")
                return
            }
        }
    }

    func testSaveCreatesParentDirectory() throws {
        let deepPath = tempDirectory
            .appendingPathComponent("a")
            .appendingPathComponent("b")
            .appendingPathComponent("c")
            .appendingPathComponent("settings.json")
        let store = JSONSettingsStore(filePath: deepPath.path)

        try store.save(AppSettings.defaultSettings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: deepPath.path))
    }

    func testOverwriteExistingSettings() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let filePath = tempDirectory.appendingPathComponent("settings.json").path
        let store = JSONSettingsStore(filePath: filePath)

        // Save first version.
        let first = AppSettings.defaultSettings
        try store.save(first)

        // Save second version with different data.
        let second = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: ["container-abc"],
            actionPreferences: ["default": "restart"],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )
        try store.save(second)

        let loaded = try store.load()
        XCTAssertEqual(loaded, second)
        XCTAssertNotEqual(loaded, first)
        XCTAssertEqual(loaded.favoriteContainerKeys, ["container-abc"])
    }
}
