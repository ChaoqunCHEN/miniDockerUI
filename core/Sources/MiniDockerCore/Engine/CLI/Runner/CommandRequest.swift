import Foundation

/// Describes a CLI command to execute.
///
/// All fields are value types, making this struct fully ``Sendable``,
/// ``Codable``, and ``Equatable`` for easy use across concurrency
/// boundaries and serialisation round-trips.
public struct CommandRequest: Sendable, Codable, Equatable {
    /// Absolute path to the executable (e.g. `/usr/local/bin/docker`).
    public let executablePath: String

    /// Arguments passed to the executable.
    public let arguments: [String]

    /// Optional environment variables to merge over the inherited process environment.
    /// When `nil`, the child process inherits the current environment unchanged.
    public let environment: [String: String]?

    /// Optional working directory for the child process.
    public let workingDirectory: String?

    /// Optional timeout in seconds. When exceeded the process is terminated
    /// and ``CoreError/processTimeout(executablePath:timeoutSeconds:)`` is thrown.
    public let timeoutSeconds: Double?

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeoutSeconds: Double? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
    }
}
