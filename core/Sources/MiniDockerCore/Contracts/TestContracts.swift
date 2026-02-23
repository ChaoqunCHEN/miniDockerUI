import Foundation

public protocol IntegrationEnvironmentProvider {
    mutating func prepare() async throws
    func endpoint() -> EngineEndpoint
    mutating func teardown() async
}

public protocol EngineTestClient {
    func listContainers() async throws -> [ContainerSummary]
    func startContainer(id: String) async throws
    func stopContainer(id: String, timeoutSeconds: Int?) async throws
    func streamEvents(since: Date?) -> AsyncThrowingStream<EventEnvelope, Error>
    func streamLogs(id: String, options: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error>
}

public protocol FixtureOrchestrator {
    func createFixtures(runID: String, descriptors: [FixtureDescriptor]) async throws -> [FixtureHandle]
    func removeFixtures(runID: String) async
}

public protocol ReadinessProbeHarness {
    func verifyTransitions(
        observations: [ReadinessObservation],
        rule: ReadinessRule,
        expectation: ReadinessProbeExpectation
    ) throws
}

public protocol LogLoadGenerator {
    func generate(containerId: String, profile: LogLoadProfile) async throws -> LogLoadResult
}
