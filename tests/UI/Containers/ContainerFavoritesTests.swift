import MiniDockerCore
import XCTest

final class ContainerFavoritesTests: XCTestCase {
    private func makeContainer(
        id: String, name: String,
        engineContextId: String = "local"
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: engineContextId, id: id, name: name,
            image: "alpine:3.20", status: "Up", health: nil,
            labels: [:], startedAt: nil
        )
    }

    func testContainerKeyFormat() {
        let container = makeContainer(id: "abc123", name: "web-server", engineContextId: "local")
        let key = ContainerGrouper.containerKey(for: container)
        XCTAssertEqual(key, "local:web-server")
    }

    func testContainerKeyDifferentContext() {
        let container = makeContainer(id: "abc", name: "web", engineContextId: "remote-prod")
        let key = ContainerGrouper.containerKey(for: container)
        XCTAssertEqual(key, "remote-prod:web")
    }

    func testToggleFavoriteAddsKey() {
        var favoriteKeys: Set<String> = []
        let container = makeContainer(id: "1", name: "web")
        let key = ContainerGrouper.containerKey(for: container)
        favoriteKeys.insert(key)
        XCTAssertTrue(favoriteKeys.contains("local:web"))
    }

    func testToggleFavoriteRemovesKey() {
        var favoriteKeys: Set<String> = ["local:web"]
        favoriteKeys.remove("local:web")
        XCTAssertTrue(favoriteKeys.isEmpty)
    }

    func testFavoritePersistenceRoundTrip() throws {
        let store = MockSettingsStore()
        let key = "local:web"

        // Add favorite
        var settings = try store.load()
        var updated = AppSettings(
            schemaVersion: settings.schemaVersion,
            favoriteContainerKeys: settings.favoriteContainerKeys.union([key]),
            actionPreferences: settings.actionPreferences,
            worktreeMappings: settings.worktreeMappings,
            readinessRules: settings.readinessRules,
            transientUIPreferences: settings.transientUIPreferences
        )
        try store.save(updated)

        // Reload and verify
        let reloaded = try store.load()
        XCTAssertTrue(reloaded.favoriteContainerKeys.contains(key))

        // Remove favorite
        settings = try store.load()
        updated = AppSettings(
            schemaVersion: settings.schemaVersion,
            favoriteContainerKeys: settings.favoriteContainerKeys.subtracting([key]),
            actionPreferences: settings.actionPreferences,
            worktreeMappings: settings.worktreeMappings,
            readinessRules: settings.readinessRules,
            transientUIPreferences: settings.transientUIPreferences
        )
        try store.save(updated)

        let final_ = try store.load()
        XCTAssertFalse(final_.favoriteContainerKeys.contains(key))
    }
}
