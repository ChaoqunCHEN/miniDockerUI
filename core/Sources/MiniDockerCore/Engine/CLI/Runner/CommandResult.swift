import Foundation

/// Captured output of a completed CLI process.
///
/// This type never throws for non-zero exit codes; callers inspect
/// ``isSuccess`` or ``exitCode`` and decide how to proceed. Use
/// ``CLICommandRunner/runChecked(_:)`` to get automatic failure throwing.
public struct CommandResult: Sendable, Equatable {
    /// Process termination status. Zero conventionally means success.
    public let exitCode: Int32

    /// Raw bytes written to the standard output pipe.
    public let stdout: Data

    /// Raw bytes written to the standard error pipe.
    public let stderr: Data

    /// Wall-clock duration of the process execution in seconds.
    public let durationSeconds: Double

    // MARK: - Computed Properties

    /// Standard output decoded as a UTF-8 string.
    public var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    /// Standard error decoded as a UTF-8 string.
    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }

    /// `true` when the process exited with code 0.
    public var isSuccess: Bool {
        exitCode == 0
    }

    public init(
        exitCode: Int32,
        stdout: Data = Data(),
        stderr: Data = Data(),
        durationSeconds: Double = 0
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationSeconds = durationSeconds
    }
}
