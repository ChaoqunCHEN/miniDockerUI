# Learnings

## 2026-02-22
1. Non-interactive integration testing requires architecture-level test interfaces early; otherwise adapter contracts drift and tests become brittle.
2. Running integration suites on both Linux and macOS increases confidence but must include strict determinism controls (fixed images, bounded retries, idempotent teardown) to avoid CI flake.
3. Defining run-ID namespace isolation and mandatory artifact capture at design time reduces debugging cost for stream/reconnect failures.

## 2026-02-21
1. A wave model without explicit `Wn-E2E` and `Wn-FIX` tasks allows defects to leak forward and increases rework cost.
2. Defining per-task `owned_paths` in the execution plan significantly reduces agent merge conflicts in parallel delivery.
3. Hard gating wave progression on quality closure is more reliable than relying on informal "test before merge" policy.

## 2026-02-22 (bootstrap)
1. Swift Package bootstrap is straightforward for app/core/tests split, but local environment validation can fail if Swift toolchain and macOS SDK patch versions diverge.
2. In sandboxed environments, SwiftPM may fail if it cannot write module/cache paths under the user home directory.
3. Keeping an Xcode project in `app/miniDockerUI.xcodeproj` provides a practical fallback workflow when command-line toolchain configuration is unstable.
4. Keep Wave task status as `blocked` when acceptance criteria depend on build/test verification that cannot be completed in the current runtime.
5. For Xcode, the app target should depend on local package product `MiniDockerCore`; compiling core sources directly in app target causes module-import drift.

## 2026-02-22 (bootstrap verification)
1. In this runtime, `swift build` and `swift test` require escalation because SwiftPM invokes `sandbox-exec`, which conflicts with the outer sandbox policy.
2. Declaring `Assets.xcassets` as an executable target resource removes unhandled-file warnings and keeps app bootstrap clean.
3. Excluding non-source docs (for example `tests/Integration/README.md`) from test targets avoids noisy SwiftPM warnings and improves signal during CI bring-up.

## 2026-02-22 (contract implementation)
1. Keeping one canonical runtime type surface (`RuntimeTypes.swift`) is critical; duplicate contract models in parallel files quickly create ambiguous type lookup and invalid redeclarations.
2. Compile-time contract tests with concrete stub adapters/providers are an effective safety net for protocol shape drift before engine implementation starts.
3. A lightweight `JSONValue` type helps preserve contract fidelity for `rawInspect`/`raw` fields without forcing premature schema commitments.

## 2026-02-22 (wave0 e2e/fix gates)
1. Explicit run IDs for E2E and rerun evidence (`run-w0-e2e-*`, `run-w0-fix-rerun-*`) make gate audits deterministic and reduce ambiguity during handoff.
2. Running `xcodebuild` app-boot smoke alongside focused `swift test --filter` checks gives better signal than only running full-package tests for Wave 0.
3. Even when no defects are found, marking `W0-FIX` as `no-op (verified)` with a concrete rerun is useful for strict wave-gate closure and downstream dependency confidence.

## 2026-02-22 (integration environment provider)
1. Using a `DockerAvailabilityChecking` protocol with dependency injection lets the test harness mock Docker presence/health without requiring Docker to be installed, keeping mock-based tests fast and deterministic.
2. For Swift 6 strict concurrency with Foundation `Process` (non-Sendable), creating the `Process` inside `withCheckedContinuation` and using its `terminationHandler` with a Sendable `CheckedContinuation` avoids capture issues -- the continuation is Sendable, and the process is passed as a parameter to the handler, not captured.
3. When multiple agents work in parallel on different tasks within the same package, a broken build in one agent's files (for example, Sendable violations in `CLICommandRunner.swift`) blocks compilation of all targets including test targets owned by other agents. This highlights the importance of per-task build isolation or fixing build-breaking errors before merging to shared branches.
4. Using `XCTSkip` for real-Docker tests is essential for CI environments where Docker may not be available, while still allowing the test to exercise the real code path on developer machines.

## 2026-02-22 (manual docker log fixtures)
1. Hosting manual-test containers in an isolated Compose directory with bind-mounted scripts keeps fixture behavior editable without image rebuilds.
2. `docker compose config` is a fast validation gate for fixture syntax and mount resolution even when the Docker daemon is unavailable.
3. For manual log-view testing, randomized but structured key-value log lines (for example `latency_ms=`, `bpm=`, `event=`) are more useful than plain free-text spam because they exercise both readability and parsing/search scenarios.

## 2026-02-22 (CLI command runner)
1. In Swift 6 strict concurrency, `DispatchWorkItem` is not Sendable. Storing it inside an `OSAllocatedUnfairLock`-protected state struct (with `nonisolated(unsafe)`) and using `@preconcurrency import Dispatch` is the cleanest workaround for timeout scheduling in `@Sendable` closures.
2. `Pipe` and `FileHandle` are Sendable in the current macOS SDK (Swift 6 / macOS 14+), so `nonisolated(unsafe)` annotations on those captures are unnecessary and produce warnings.
3. When creating a `Task` inside a test method that captures a property of the test class (e.g. `runner`), Swift 6 flags it as a sending violation since `XCTestCase` is not Sendable. The fix is to copy the value into a local `let` before the `Task` closure.
4. Reading stdout/stderr pipes after process termination via `readDataToEndOfFile()` avoids pipe buffer deadlocks that occur when trying to read concurrently with a running process that produces large output.
5. Using `withTaskCancellationHandler` + `withCheckedThrowingContinuation` with shared lock state is a reliable pattern for bridging Foundation `Process` into Swift concurrency with proper cancellation and timeout support.
6. **Critical deadlock pattern**: When using `withCheckedThrowingContinuation` with `Process.terminationHandler`, the `onCancel` handler must NOT set `isFinished = true` and skip continuation resumption. If `onCancel` marks finished and terminates the process, the `terminationHandler` sees `isFinished` and skips resuming the continuation — causing a permanent hang. The fix: `onCancel` and timeout handlers should only set flags (`didCancel`/`didTimeout`) and terminate the process. The `terminationHandler` is the **single point** that resumes the continuation, checking the flags to determine the error type.

## 2026-02-22 (W1-BUILD-STATE-001: settings store + migration + keychain)
1. Making `MigrationStep` store a `@Sendable` closure requires all captured state to be `Sendable`; this encourages pure-functional migration transforms that reconstruct `AppSettings` rather than mutating shared state.
2. The `SettingsMigrator.buildChain` algorithm walks steps linearly by matching `fromVersion` to current position, which is simple and correct but assumes no duplicate `fromVersion` entries; adding a uniqueness check would guard against accidental step registration bugs.
3. Testing keychain logic via an `InMemoryKeychainStore` mock is essential because `SecItem*` APIs require keychain entitlements that are not available in sandboxed test runners or CI environments.
4. `JSONSettingsStore.save` creating parent directories with `withIntermediateDirectories: true` prevents first-launch failures when the settings directory does not yet exist.
5. Using `Data.write(to:options:.atomic)` for settings persistence prevents partial-write corruption on crash.

## 2026-02-22 (Wave 2: CLI parsers, log buffer, worktree validation)
1. Docker `ps --format json` outputs NDJSON (one JSON object per line), not a JSON array. Using `JSONSerialization` per line is simpler than trying to decode the entire output as a single document.
2. Docker's `Status` field embeds health status in parentheses (e.g. "Up 2 hours (healthy)"). Extracting health by parsing the last parenthesized segment is more robust than pattern-matching the full status string.
3. Docker's label format in `docker ps --format json` is comma-separated `key=value` pairs where values can contain `=`. Always split on the first `=` per pair.
4. For RFC3339Nano timestamps, Foundation's `ISO8601DateFormatter` only supports millisecond precision. Manual extraction of the fractional part (up to 9 digits) with `addingTimeInterval()` preserves nanosecond precision without external dependencies.
5. `OSAllocatedUnfairLock` works well for the ring buffer pattern: take the lock for the minimum duration (read/mutate the dictionary entry), release before any user callbacks or allocations.
6. When implementing a ring buffer with both line and byte caps, eviction must loop (evicting oldest repeatedly) until **both** constraints are satisfied, since a single large entry might require evicting multiple smaller ones.
7. Worktree validation should be a pure function layer with no filesystem access — this makes it trivially testable and separates validation from execution. The planner takes `runningContainerIds` as a parameter rather than querying Docker.
8. Path normalization (stripping trailing `/`) must be applied consistently across all path comparisons. Using a shared `normalizePath()` helper prevents subtle prefix-matching bugs.
9. Separating `WorktreeValidationError` from `CoreError` provides granular per-field validation feedback suitable for UI display without polluting the command/protocol error taxonomy.

## 2026-02-23 (Wave 3: CLIEngineAdapter + ReadinessEvaluator + App Shell)
1. Extracting a `CommandRunning` protocol from the concrete `CLICommandRunner` struct is essential for adapter-level unit testing — it allows injecting a `MockCommandRunner` that returns canned responses without launching real processes.
2. A `DataLineAccumulator` (buffered newline splitter) is a reusable primitive for any CLI stream-to-parsed-object pipeline. Keeping it as a small `mutating struct` with `feed()` and `flush()` makes it independently testable.
3. The `EngineAdapter` protocol must inherit `Sendable` for Swift 6 strict concurrency when stored as `any EngineAdapter` in `@MainActor`-isolated ViewModels. Without this, the compiler rejects cross-actor usage.
4. Using `@Observable` (Observation framework) instead of `ObservableObject` eliminates `@Published` boilerplate and provides more granular tracking of property access in SwiftUI views.
5. When constructing detail ViewModels in NavigationSplitView's detail pane, applying `.id(selectedId)` forces SwiftUI to recreate the view (and ViewModel) on selection change, ensuring log streams are properly cancelled and restarted for the new container.
6. Log entry capping in the ViewModel (e.g., 5000 lines with `removeFirst` trimming) provides a simple backpressure mechanism before the full `LogRingBuffer` integration in later waves.
7. For streaming methods (`streamEvents`, `streamLogs`), wrapping `runner.stream()` in a new `AsyncThrowingStream` that transforms `Data` chunks into parsed domain objects via `DataLineAccumulator` keeps the adapter's public API clean while handling all buffering internally.
8. The event stream pattern (background Task that iterates events and refreshes the container list on each event) provides near-real-time UI updates without polling, but needs proper cancellation via `Task.cancel()` on view disappear to avoid process leaks.

## 2026-02-24 (Wave 3 E2E: integration scenario tests)
1. Writing integration-level scenario tests that exercise the adapter through `MockCommandRunner` (not just unit-level individual method tests) catches end-to-end data flow issues like NDJSON parsing across multiple containers, stream chunking reassembly, and sequence numbering correctness.
2. Cross-integration tests (LogRingBuffer → ReadinessEvaluator, LogSearchEngine → ReadinessEvaluator) validate that types flowing between components are compatible and that the boundary `windowStart` date filtering works correctly across the full pipeline.
3. The `ReadinessEvaluator` uses `entry.timestamp < windowStart` for stale-line rejection, meaning entries at exactly `windowStart` are **included** (boundary-inclusive). This was verified with a dedicated integration test and should be documented for future consumers.
4. The adapter's streaming methods correctly pass through all log lines without capping — the 5000-line cap is purely a ViewModel responsibility. This separation was verified by feeding 6000 lines through the adapter and confirming all were yielded.
5. When Docker is available locally, real-Docker integration tests (`testRealListContainersReturnsArray`, `testRealInspectKnownFixture`) exercise the full CLI → parser → adapter pipeline against the actual Docker daemon, catching issues that mock-based tests cannot (e.g., JSON format changes, encoding issues).
