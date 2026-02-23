import Foundation
@testable import MiniDockerCore
import XCTest

final class PublicTestContractTests: XCTestCase {
    func testIntegrationEnvironmentProviderContractCompiles() async throws {
        var provider = StubIntegrationProvider()
        let contract: any IntegrationEnvironmentProvider = provider
        XCTAssertEqual(contract.endpoint().endpointType, .local)

        try await provider.prepare()
        XCTAssertTrue(provider.isPrepared)
        await provider.teardown()
        XCTAssertFalse(provider.isPrepared)
    }

    func testEngineTestClientContractCompilesAndProducesStreams() async throws {
        let client = StubEngineClient()
        let contract: any EngineTestClient = client

        let containers = try await contract.listContainers()
        XCTAssertEqual(containers.first?.id, "fixture-1")

        var eventCount = 0
        for try await _ in contract.streamEvents(since: nil) {
            eventCount += 1
        }
        XCTAssertEqual(eventCount, 1)
    }

    func testFixtureOrchestratorContractCompiles() async throws {
        let orchestrator = StubFixtureOrchestrator()
        let contract: any FixtureOrchestrator = orchestrator

        let handles = try await contract.createFixtures(
            runID: "run-1",
            descriptors: [FixtureDescriptor(key: "web", image: "nginx:latest", command: ["nginx"], environment: [:])]
        )
        XCTAssertEqual(handles.first?.key, "web")
        await contract.removeFixtures(runID: "run-1")
    }

    func testReadinessProbeHarnessContractCompiles() throws {
        let harness = StubReadinessHarness()
        let contract: any ReadinessProbeHarness = harness
        let now = Date(timeIntervalSince1970: 100)
        let observations = [
            ReadinessObservation(signal: .healthy, observedAt: now, details: nil),
            ReadinessObservation(signal: .regexMatched, observedAt: now.addingTimeInterval(1), details: "ready"),
        ]
        let rule = ReadinessRule(
            mode: .healthThenRegex,
            regexPattern: "ready",
            mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let expectation = ReadinessProbeExpectation(
            expectedReady: true,
            windowStart: now.addingTimeInterval(-1),
            windowEnd: now.addingTimeInterval(2)
        )

        XCTAssertNoThrow(try contract.verifyTransitions(observations: observations, rule: rule, expectation: expectation))
    }

    func testLogLoadGeneratorContractCompiles() async throws {
        let generator = StubLogLoadGenerator()
        let contract: any LogLoadGenerator = generator
        let result = try await contract.generate(
            containerId: "fixture-1",
            profile: LogLoadProfile(lineCount: 1000, bytesPerLine: 64, intervalMilliseconds: 0)
        )

        XCTAssertEqual(result.generatedLines, 1000)
        XCTAssertEqual(result.generatedBytes, 64000)
    }
}

private struct StubIntegrationProvider: IntegrationEnvironmentProvider {
    var isPrepared = false

    mutating func prepare() async throws {
        isPrepared = true
    }

    func endpoint() -> EngineEndpoint {
        EngineEndpoint(endpointType: .local, address: "unix:///var/run/docker.sock")
    }

    mutating func teardown() async {
        isPrepared = false
    }
}

private struct StubEngineClient: EngineTestClient {
    func listContainers() async throws -> [ContainerSummary] {
        [
            ContainerSummary(
                engineContextId: "local",
                id: "fixture-1",
                name: "fixture-web",
                image: "nginx:latest",
                status: "running",
                health: .healthy,
                labels: [:],
                startedAt: nil
            ),
        ]
    }

    func startContainer(id _: String) async throws {}

    func stopContainer(id _: String, timeoutSeconds _: Int?) async throws {}

    func streamEvents(since _: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                EventEnvelope(
                    sequence: 1,
                    eventAt: Date(timeIntervalSince1970: 10),
                    containerId: "fixture-1",
                    action: "start",
                    attributes: [:],
                    source: "docker",
                    raw: nil
                )
            )
            continuation.finish()
        }
    }

    func streamLogs(id: String, options _: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                LogEntry(
                    engineContextId: "local",
                    containerId: id,
                    stream: .stdout,
                    timestamp: Date(timeIntervalSince1970: 11),
                    message: "fixture log"
                )
            )
            continuation.finish()
        }
    }
}

private struct StubFixtureOrchestrator: FixtureOrchestrator {
    func createFixtures(runID: String, descriptors: [FixtureDescriptor]) async throws -> [FixtureHandle] {
        descriptors.map { FixtureHandle(key: $0.key, containerId: "\(runID)-\($0.key)") }
    }

    func removeFixtures(runID _: String) async {}
}

private struct StubReadinessHarness: ReadinessProbeHarness {
    func verifyTransitions(
        observations: [ReadinessObservation],
        rule: ReadinessRule,
        expectation: ReadinessProbeExpectation
    ) throws {
        if expectation.expectedReady {
            let hasSignal = observations.contains { $0.signal == .healthy || $0.signal == .regexMatched }
            if !hasSignal {
                throw ContractError.missingReadinessSignal
            }
        }
        if rule.mode == .regexOnly, rule.regexPattern == nil {
            throw ContractError.invalidRule
        }
    }
}

private struct StubLogLoadGenerator: LogLoadGenerator {
    func generate(containerId _: String, profile: LogLoadProfile) async throws -> LogLoadResult {
        LogLoadResult(
            generatedLines: profile.lineCount,
            generatedBytes: profile.lineCount * profile.bytesPerLine,
            startedAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 21)
        )
    }
}

private enum ContractError: Error {
    case missingReadinessSignal
    case invalidRule
}
