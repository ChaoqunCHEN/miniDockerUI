import Foundation

/// A single forward migration step between two schema versions.
public struct MigrationStep: Sendable {
    public let fromVersion: SchemaVersion
    public let toVersion: SchemaVersion
    public let migrate: @Sendable (AppSettings) throws -> AppSettings

    public init(
        from fromVersion: SchemaVersion,
        to toVersion: SchemaVersion,
        migrate: @escaping @Sendable (AppSettings) throws -> AppSettings
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migrate = migrate
    }
}

/// Applies an ordered chain of `MigrationStep` instances to advance
/// settings from their current schema version to a target version.
///
/// Migration is forward-only: downgrades are rejected and gaps in the
/// step chain cause an error.
public struct SettingsMigrator: Sendable {
    public let steps: [MigrationStep]

    public init(steps: [MigrationStep]) {
        self.steps = steps
    }

    /// Migrate settings forward from their current `schemaVersion` to `target`.
    ///
    /// - Returns the settings unchanged if already at `target`.
    /// - Throws `CoreError.schemaDowngradeRejected` if current version exceeds `target`.
    /// - Throws `CoreError.schemaMigrationUnsupported` if no contiguous chain of
    ///   steps connects current version to `target`.
    public func migrate(_ settings: AppSettings, to target: SchemaVersion) throws -> AppSettings {
        let current = try SchemaVersion(parsing: settings.schemaVersion)

        if current == target {
            return settings
        }

        if current > target {
            throw CoreError.schemaDowngradeRejected(
                current: current.description,
                requested: target.description
            )
        }

        // Build ordered chain from current to target.
        let chain = try buildChain(from: current, to: target)

        var result = settings
        for step in chain {
            result = try step.migrate(result)
            // Update schemaVersion to reflect the step's target.
            result = AppSettings(
                schemaVersion: step.toVersion.description,
                favoriteContainerKeys: result.favoriteContainerKeys,
                actionPreferences: result.actionPreferences,
                worktreeMappings: result.worktreeMappings,
                readinessRules: result.readinessRules,
                transientUIPreferences: result.transientUIPreferences
            )
        }

        return result
    }

    // MARK: - Private

    /// Build a contiguous chain of migration steps from `start` to `end`.
    ///
    /// At each position the algorithm finds the unique step whose `fromVersion`
    /// matches the current position. If no such step exists, or if the chain
    /// does not reach `end`, the migration is unsupported.
    private func buildChain(from start: SchemaVersion, to end: SchemaVersion) throws -> [MigrationStep] {
        var chain: [MigrationStep] = []
        var position = start

        while position < end {
            guard let nextStep = steps.first(where: { $0.fromVersion == position }) else {
                throw CoreError.schemaMigrationUnsupported(
                    from: start.description,
                    to: end.description
                )
            }
            chain.append(nextStep)
            position = nextStep.toVersion
        }

        guard position == end else {
            throw CoreError.schemaMigrationUnsupported(
                from: start.description,
                to: end.description
            )
        }

        return chain
    }
}
