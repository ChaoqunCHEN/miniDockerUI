import Foundation

/// Abstraction over CLI command execution for testability.
///
/// ``CLICommandRunner`` is the production implementation. Tests inject
/// a mock conforming to this protocol.
public protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandResult
    func runChecked(_ request: CommandRequest) async throws -> CommandResult
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error>
}

extension CLICommandRunner: CommandRunning {}
