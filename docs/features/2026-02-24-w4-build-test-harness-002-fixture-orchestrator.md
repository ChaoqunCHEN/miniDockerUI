# W4-BUILD-TEST-HARNESS-002: Fixture Orchestrator & Lifecycle Scenarios

## Date
2026-02-24

## Status
Completed

## Summary
Implements `DockerFixtureOrchestrator` conforming to the `FixtureOrchestrator` protocol from MiniDockerCore, plus comprehensive lifecycle test scenarios for container create/start/stop/restart, list bootstrap, event stream reconciliation, and event stream recovery.

## Files Created

### Harness / Fixtures
1. `/tests/Integration/Harness/Fixtures/FixtureContainerState.swift` — Enum for desired container states (`created`, `running`, `stopped`)
2. `/tests/Integration/Harness/Fixtures/DockerFixtureOrchestrator.swift` — Full orchestrator implementation using `CommandRunning` protocol
3. `/tests/Integration/Harness/Fixtures/FixtureOrchestratorTests.swift` — 12 tests (10 mock-based, 2 real Docker)

### Scenarios / Lifecycle
4. `/tests/Integration/Scenarios/Lifecycle/ContainerLifecycleTests.swift` — 9 tests exercising full lifecycle through `CLIEngineAdapter`
5. `/tests/Integration/Scenarios/Lifecycle/ContainerListBootstrapTests.swift` — 6 tests for list bootstrap and event reconciliation
6. `/tests/Integration/Scenarios/Lifecycle/EventStreamRecoveryTests.swift` — 4 tests for stream recovery, reconnect, `--since` replay, and concurrent actions

## Design Decisions

### Container Naming Convention
All fixture containers use `mdui-test-{runID}-{descriptorKey}` naming, enabling:
- Easy identification in `docker ps`
- Bulk cleanup via `--filter name=mdui-test-{runID}`
- No collision between concurrent test runs

### Partial Failure Cleanup
If any fixture creation fails mid-batch, `removeFixtures(runID:)` is called before rethrowing, ensuring no orphaned containers.

### Error Swallowing in removeFixtures
`removeFixtures` never throws — all Docker errors are swallowed to ensure cleanup is always best-effort and idempotent.

### Swift 6 Strict Concurrency
All closures captured in Task blocks use explicit capture lists with `@Sendable` annotations to satisfy Swift 6 strict concurrency checking.

### XCTSkip Guard Pattern
All real Docker tests use `try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"))` consistent with existing patterns in `CLIAdapterLifecycleTests.swift`.

## Test Counts
- Fixture orchestrator: 12 tests (mock + real Docker)
- Container lifecycle: 9 tests (all real Docker, XCTSkip guarded)
- List bootstrap & events: 6 tests (all real Docker, XCTSkip guarded)
- Event stream recovery: 4 tests (all real Docker, XCTSkip guarded)
- **Total new tests: 31**

## Verification
- `make autoformat`: passed (0 files reformatted)
- `make build`: passed (Build complete!)
- `swift test --skip IntegrationHarnessTests`: 281 tests, 0 failures
