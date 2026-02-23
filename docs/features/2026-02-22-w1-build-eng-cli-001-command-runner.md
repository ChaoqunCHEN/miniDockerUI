# W1-BUILD-ENG-CLI-001: Generic Async CLI Command Runner

## Date: 2026-02-22
## Task ID: W1-BUILD-ENG-CLI-001
## Wave: 1
## Lane: engine
## Status: completed

## Overview
Implement a stateless, Sendable CLI command runner that wraps Foundation `Process` for async execution. This is the lowest-level building block for the CLI engine adapter path.

## Design

### New Types
1. **CommandRequest** - Value type describing a CLI command to execute (executable, args, env, working directory, timeout).
2. **CommandResult** - Value type capturing process output (exit code, stdout, stderr, duration).
3. **CLICommandRunner** - Stateless Sendable struct providing `run()`, `runChecked()`, and `stream()` methods.

### Key Design Decisions
- **Stateless struct**: No stored state; each call is independent. Satisfies Sendable trivially.
- **Process isolation**: Foundation `Process` is NOT Sendable. Use `OSAllocatedUnfairLock<Process?>` to safely share process reference between cancellation handler and continuation.
- **Pipe deadlock avoidance**: Read stdout/stderr AFTER process terminates using `readDataToEndOfFile()`.
- **Timeout**: DispatchWorkItem scheduled on a queue; terminates process after deadline.
- **Cancellation**: `withTaskCancellationHandler` to terminate process on Swift concurrency cancellation.
- **Duration**: `ContinuousClock` for monotonic timing.
- **Environment merging**: If `CommandRequest.environment` is provided, merge it over `ProcessInfo.processInfo.environment`.

### Error Mapping
- Process launch failure -> `CoreError.processLaunchFailed`
- Non-zero exit (runChecked only) -> `CoreError.processNonZeroExit`
- Timeout -> `CoreError.processTimeout`
- Cancellation -> `CoreError.processCancelled`

### File Layout
```
core/Sources/MiniDockerCore/Engine/CLI/Runner/
  CommandRequest.swift
  CommandResult.swift
  CLICommandRunner.swift

core/Tests/MiniDockerCoreTests/Engine/CLI/Runner/
  CLICommandRunnerTests.swift
  CommandTypesTests.swift
```

## Test Plan
- Echo success, non-zero exit, stderr capture
- runChecked throws on failure
- Timeout with sleep 60 + 0.5s timeout
- Cancellation with Task cancel after 0.1s
- Launch failure with nonexistent binary
- Environment variable passing
- Stream yields data chunks
- Codable round-trip for CommandRequest
- isSuccess and string conversion for CommandResult

## Acceptance Criteria
- All tests pass with `swift test --skip IntegrationHarnessTests`
- `swift build` compiles cleanly under Swift 6 strict concurrency
- No modifications to existing files
