import Foundation

/// Project-wide typed error taxonomy.
///
/// Categories follow the architecture document:
/// - Dependency: required binary or service not available
/// - Context: endpoint or environment unreachable
/// - Command/Protocol: process execution failures
/// - Parse/Contract: output cannot be understood or violates expectations
/// - I/O: file system and serialization failures
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

    // MARK: - I/O errors

    case fileReadFailed(path: String, reason: String)
    case fileWriteFailed(path: String, reason: String)
    case directoryCreateFailed(path: String, reason: String)
    case decodingFailed(context: String, reason: String)
    case encodingFailed(context: String, reason: String)

    // MARK: - Policy errors

    case operationNotPermitted(action: String, reason: String)
    case schemaMigrationUnsupported(from: String, to: String)
    case schemaDowngradeRejected(current: String, requested: String)
    case keychainOperationFailed(operation: String, osStatus: Int32)

    // MARK: - Compose errors

    case composeRecreationFailed(projectName: String, service: String, stderr: String)

    // MARK: - Git errors

    case gitNotARepository(directory: String)
    case gitWorktreeListFailed(repoRoot: String, reason: String)
}

// MARK: - LocalizedError

extension CoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .dependencyNotFound(name, searchedPaths):
            "Required dependency '\(name)' not found (searched: \(searchedPaths.joined(separator: ", ")))"
        case let .dependencyVersionUnsupported(name, found, required):
            "Dependency '\(name)' version \(found) is unsupported (requires \(required))"
        case let .endpointUnreachable(endpoint, reason):
            "Endpoint '\(endpoint.address)' unreachable: \(reason)"
        case let .contextNotConfigured(contextId):
            "Engine context '\(contextId)' is not configured"
        case let .processLaunchFailed(path, reason):
            "Failed to launch '\(path)': \(reason)"
        case let .processNonZeroExit(path, exitCode, stderr):
            "'\(path)' exited with code \(exitCode): \(stderr.prefix(200))"
        case let .processTimeout(path, timeout):
            "'\(path)' timed out after \(timeout)s"
        case let .processCancelled(path):
            "'\(path)' was cancelled"
        case let .outputParseFailure(context, rawSnippet):
            "Failed to parse output in \(context): \(rawSnippet.prefix(100))"
        case let .contractViolation(expected, actual):
            "Contract violation: expected \(expected), got \(actual)"
        case let .fileReadFailed(path, reason):
            "Failed to read '\(path)': \(reason)"
        case let .fileWriteFailed(path, reason):
            "Failed to write '\(path)': \(reason)"
        case let .directoryCreateFailed(path, reason):
            "Failed to create directory '\(path)': \(reason)"
        case let .decodingFailed(context, reason):
            "Decoding failed in \(context): \(reason)"
        case let .encodingFailed(context, reason):
            "Encoding failed in \(context): \(reason)"
        case let .operationNotPermitted(action, reason):
            "Operation '\(action)' not permitted: \(reason)"
        case let .schemaMigrationUnsupported(from, to):
            "Schema migration from \(from) to \(to) is unsupported"
        case let .schemaDowngradeRejected(current, requested):
            "Schema downgrade from \(current) to \(requested) is not allowed"
        case let .keychainOperationFailed(operation, osStatus):
            "Keychain \(operation) failed (status: \(osStatus))"
        case let .composeRecreationFailed(projectName, service, stderr):
            "Failed to recreate service '\(service)' in project '\(projectName)': \(stderr.prefix(200))"
        case let .gitNotARepository(directory):
            "'\(directory)' is not inside a git repository"
        case let .gitWorktreeListFailed(repoRoot, reason):
            "Failed to list worktrees for '\(repoRoot)': \(reason)"
        }
    }
}
