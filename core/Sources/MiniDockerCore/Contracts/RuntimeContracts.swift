import Foundation

public protocol EngineAdapter: Sendable {
    func listContainers() async throws -> [ContainerSummary]
    func inspectContainer(id: String) async throws -> ContainerDetail
    func startContainer(id: String) async throws
    func stopContainer(id: String, timeoutSeconds: Int?) async throws
    func restartContainer(id: String, timeoutSeconds: Int?) async throws
    func streamEvents(since: Date?) -> AsyncThrowingStream<EventEnvelope, Error>
    func streamLogs(id: String, options: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error>
}

public protocol AppSettingsStore {
    func load() throws -> AppSettingsSnapshot
    func save(_ snapshot: AppSettingsSnapshot) throws
}
