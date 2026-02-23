import Foundation

/// Project-wide typed error taxonomy.
///
/// Categories follow the architecture document:
/// - Dependency: required binary or service not available
/// - Context: endpoint or environment unreachable
/// - Command/Protocol: process execution failures
/// - Parse/Contract: output cannot be understood or violates expectations
/// - Policy: disallowed operation or invalid configuration transition
public enum CoreError: Error, Sendable, Equatable {
    // MARK: - Dependency errors

    case dependencyNotFound(name: String, searchedPaths: [String])
    case dependencyVersionUnsupported(name: String, found: String, required: String)

    // MARK: - Context errors

    case endpointUnreachable(endpoint: EngineEndpoint, reason: String)
    case contextNotConfigured(contextId: String)

    // MARK: - Command/Protocol errors

    case processLaunchFailed(executablePath: String, reason: String)
    case processNonZeroExit(executablePath: String, exitCode: Int32, stderr: String)
    case processTimeout(executablePath: String, timeoutSeconds: Double)
    case processCancelled(executablePath: String)

    // MARK: - Parse/Contract errors

    case outputParseFailure(context: String, rawSnippet: String)
    case contractViolation(expected: String, actual: String)

    // MARK: - Policy errors

    case operationNotPermitted(action: String, reason: String)
    case schemaMigrationUnsupported(from: String, to: String)
    case schemaDowngradeRejected(current: String, requested: String)
    case keychainOperationFailed(operation: String, osStatus: Int32)
}
