@testable import MiniDockerCore
import XCTest

final class SettingsMigrationTests: XCTestCase {
    // MARK: - No migration needed

    func testNoMigrationNeededAtTarget() throws {
        let migrator = SettingsMigrator(steps: [])
        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: ["my-container"],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 1, minor: 0, patch: 0)
        let result = try migrator.migrate(settings, to: target)
        XCTAssertEqual(result, settings)
    }

    // MARK: - Single step

    func testSingleStepMigration() throws {
        let step = MigrationStep(
            from: SchemaVersion(major: 1, minor: 0, patch: 0),
            to: SchemaVersion(major: 1, minor: 1, patch: 0)
        ) { settings in
            // Add a default action preference during migration.
            var prefs = settings.actionPreferences
            prefs["logLevel"] = "info"
            return AppSettings(
                schemaVersion: settings.schemaVersion,
                favoriteContainerKeys: settings.favoriteContainerKeys,
                actionPreferences: prefs,
                worktreeMappings: settings.worktreeMappings,
                readinessRules: settings.readinessRules,
                transientUIPreferences: settings.transientUIPreferences
            )
        }

        let migrator = SettingsMigrator(steps: [step])
        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: [],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 1, minor: 1, patch: 0)
        let result = try migrator.migrate(settings, to: target)
        XCTAssertEqual(result.actionPreferences["logLevel"], "info")
        XCTAssertEqual(result.schemaVersion, "1.1.0")
    }

    // MARK: - Multi step

    func testMultiStepMigration() throws {
        let step1 = MigrationStep(
            from: SchemaVersion(major: 1, minor: 0, patch: 0),
            to: SchemaVersion(major: 1, minor: 1, patch: 0)
        ) { settings in
            var prefs = settings.actionPreferences
            prefs["step1"] = "applied"
            return AppSettings(
                schemaVersion: settings.schemaVersion,
                favoriteContainerKeys: settings.favoriteContainerKeys,
                actionPreferences: prefs,
                worktreeMappings: settings.worktreeMappings,
                readinessRules: settings.readinessRules,
                transientUIPreferences: settings.transientUIPreferences
            )
        }

        let step2 = MigrationStep(
            from: SchemaVersion(major: 1, minor: 1, patch: 0),
            to: SchemaVersion(major: 1, minor: 2, patch: 0)
        ) { settings in
            var prefs = settings.actionPreferences
            prefs["step2"] = "applied"
            return AppSettings(
                schemaVersion: settings.schemaVersion,
                favoriteContainerKeys: settings.favoriteContainerKeys,
                actionPreferences: prefs,
                worktreeMappings: settings.worktreeMappings,
                readinessRules: settings.readinessRules,
                transientUIPreferences: settings.transientUIPreferences
            )
        }

        let migrator = SettingsMigrator(steps: [step1, step2])
        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: [],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 1, minor: 2, patch: 0)
        let result = try migrator.migrate(settings, to: target)
        XCTAssertEqual(result.actionPreferences["step1"], "applied")
        XCTAssertEqual(result.actionPreferences["step2"], "applied")
        XCTAssertEqual(result.schemaVersion, "1.2.0")
    }

    // MARK: - Downgrade rejected

    func testDowngradeRejected() {
        let migrator = SettingsMigrator(steps: [])
        let settings = AppSettings(
            schemaVersion: "2.0.0",
            favoriteContainerKeys: [],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 1, minor: 0, patch: 0)
        XCTAssertThrowsError(try migrator.migrate(settings, to: target)) { error in
            guard case let CoreError.schemaDowngradeRejected(current, requested) = error else {
                XCTFail("Expected CoreError.schemaDowngradeRejected, got \(error)")
                return
            }
            XCTAssertEqual(current, "2.0.0")
            XCTAssertEqual(requested, "1.0.0")
        }
    }

    // MARK: - No path

    func testNoPathThrows() {
        let migrator = SettingsMigrator(steps: [])
        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: [],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 3, minor: 0, patch: 0)
        XCTAssertThrowsError(try migrator.migrate(settings, to: target)) { error in
            guard case let CoreError.schemaMigrationUnsupported(from, to) = error else {
                XCTFail("Expected CoreError.schemaMigrationUnsupported, got \(error)")
                return
            }
            XCTAssertEqual(from, "1.0.0")
            XCTAssertEqual(to, "3.0.0")
        }
    }

    // MARK: - Version update

    func testMigrationUpdatesSchemaVersion() throws {
        let step = MigrationStep(
            from: SchemaVersion(major: 1, minor: 0, patch: 0),
            to: SchemaVersion(major: 1, minor: 1, patch: 0)
        ) { settings in
            settings
        }

        let migrator = SettingsMigrator(steps: [step])
        let settings = AppSettings(
            schemaVersion: "1.0.0",
            favoriteContainerKeys: [],
            actionPreferences: [:],
            worktreeMappings: [],
            readinessRules: [:],
            transientUIPreferences: [:]
        )

        let target = SchemaVersion(major: 1, minor: 1, patch: 0)
        let result = try migrator.migrate(settings, to: target)
        XCTAssertEqual(result.schemaVersion, target.description)
    }
}
