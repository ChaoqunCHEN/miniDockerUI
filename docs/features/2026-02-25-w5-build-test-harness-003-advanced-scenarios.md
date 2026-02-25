# W5-BUILD-TEST-HARNESS-003: Advanced Scenario Test Suite

## Date
2026-02-25

## Task
Implement the advanced integration scenario test matrix for Wave 5, covering log burst, search, stream disconnect/recovery, state resync after gap, worktree switch, and worktree readiness verification.

## Status
completed

## Owned Paths
- `/tests/Integration/Scenarios/Logs/**`
- `/tests/Integration/Scenarios/Recovery/**`
- `/tests/Integration/Scenarios/Worktrees/**`
- `/tests/Integration/Scenarios/ScenarioTestHelpers.swift`

## Design

### Architecture
All test files live under `tests/Integration/` in the `IntegrationHarnessTests` target, which auto-discovers Swift files. No changes to Package.swift needed.

### Files Created

1. **ScenarioTestHelpers.swift** — Shared utilities:
   - `ScenarioMockCommandRunner`: Thread-safe mock using `OSAllocatedUnfairLock` for Swift 6 strict concurrency
   - `LogEntryFactory`: Deterministic log entry and batch generation
   - `ContainerSummaryFactory`, `EventEnvelopeFactory`: Convenience factories
   - `skipUnlessDockerAvailable()`, `sleepDescriptor()`: Common test helpers

2. **Logs/DockerLogLoadGenerator.swift** — `LogLoadGenerator` protocol implementation:
   - `SyntheticLogLoadGenerator`: Generates `LogLoadResult` in memory
   - `BufferPopulatingLogLoadGenerator`: Generates and appends entries to a `LogRingBuffer`

3. **Logs/LogBurstIntegrationTests.swift** — 7 tests (5 mock + 2 real Docker):
   - Line cap enforcement with dropOldest
   - Byte cap enforcement with dropOldest
   - dropNewest rejection of overflow
   - Search correctness after 50K-entry burst
   - Multi-container independent caps
   - Real Docker log burst into capped buffer
   - Real Docker burst + search correctness

4. **Logs/LogStreamSearchTests.swift** — 5 mock tests:
   - Stream filter (stdout vs stderr separation)
   - Time-windowed search
   - maxResults limiting
   - Regex search under burst load
   - Case-insensitive search

5. **Recovery/StreamDisconnectRecoveryTests.swift** — 7 tests (5 mock + 2 real Docker):
   - Disconnect transitions state to disconnected
   - Resync snapshot replaces container state
   - Reconnect with since replays events
   - Multiple disconnect/reconnect cycles
   - Action during disconnect reflects in resync
   - Real Docker disconnect and resync
   - Real Docker reconnect with since replay

6. **Recovery/StateResyncAfterGapTests.swift** — 5 mock tests:
   - Sequence gap triggers resyncRequired
   - Resync snapshot resolves gap
   - Batch apply stops at first gap
   - Fresh sequence after resync accepted
   - Concurrent access during resync (thread safety)

7. **Worktrees/WorktreeSwitchIntegrationTests.swift** — 8 tests (7 mock + 1 real Docker):
   - Full switch flow with mock adapter
   - ifRunning policy with running container
   - ifRunning policy with non-running container
   - never policy skips restart
   - always policy always restarts
   - Same worktree rejected
   - Outside-repo worktree rejected
   - Real Docker switch, restart, and verify state

8. **Worktrees/WorktreeReadinessVerificationTests.swift** — 8 tests (6 mock + 2 real Docker):
   - Stale line rejection after restart
   - Fresh ready line after restart succeeds
   - Health check short-circuits after restart
   - Timestamp window boundary inclusiveness
   - Buffer-to-search-to-evaluator pipeline
   - Partial matches do not satisfy readiness
   - Real Docker restart and readiness via logs
   - Real Docker stale lines from previous lifecycle

### Test Count Summary
- Total: 40 tests
- Mock-only: 33 tests
- Real Docker (guarded with XCTSkip): 7 tests

### Key Patterns
- All mock types use `@unchecked Sendable` with `OSAllocatedUnfairLock` for Swift 6 strict concurrency
- Real Docker tests guarded with `try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker"))`
- `DockerFixtureOrchestrator` for real Docker fixture lifecycle with deferred cleanup
- Async tests use `func testFoo() async throws` pattern
