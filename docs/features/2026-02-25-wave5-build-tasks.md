# Wave 5 Build Tasks — Advanced Features

**Date:** 2026-02-25
**Status:** In Progress

## Overview
Wave 5 introduces three parallel BUILD tasks: stream supervision with recovery, advanced UI features (logs/readiness/worktrees), and integration test scenarios.

---

## W5-BUILD-ENG-CLI-004: Stream Supervisor & Recovery

**Status:** Complete
**Lane:** Engine

### Problem
AppViewModel had ad-hoc inline retry logic violating the "replaceable adapters" principle. No deterministic state machine, no `markDisconnected()` or `applyResyncSnapshot()` integration.

### Implementation
Created `EventStreamSupervisor` layer sitting ABOVE `EngineAdapter`:

**New Files:**
- `core/Sources/MiniDockerCore/Engine/CLI/Streams/BackoffPolicy.swift` — exponential backoff config (initialDelay, maxDelay, maxRetries, multiplier)
- `core/Sources/MiniDockerCore/Engine/CLI/Streams/SupervisorPhase.swift` — state machine enum (idle/connecting/streaming/disconnected/backingOff/resyncing/exhausted/stopped)
- `core/Sources/MiniDockerCore/Engine/CLI/Streams/SupervisorEvent.swift` — event enum (dockerEvent/phaseChanged/resyncCompleted)
- `core/Sources/MiniDockerCore/Engine/CLI/Streams/EventStreamSupervisor.swift` — core supervisor logic

**Test Files:**
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Streams/BackoffPolicyTests.swift` (7 tests)
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Streams/SupervisorPhaseTests.swift` (3 tests)
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Streams/EventStreamSupervisorTests.swift` (11 tests)

**Total:** 4 source files, 3 test files, 21 new tests (all passing, 308 total)

### Design Decisions
- Supervisor emits `SupervisorEvent` stream; consumer (AppViewModel) drives state mutations
- `ContinuousClock.sleep(for:)` for cancellation-safe backoff
- Consecutive failure counter resets on successful stream connection
- Resync failures don't consume retry attempts
- Clean stream end triggers reconnect (Docker daemon graceful shutdown)

---

## W5-BUILD-UI-003: Advanced Features UI

**Status:** In Progress
**Lane:** UI

### Deliverables
- LogRingBuffer integration into ContainerDetailViewModel (replacing 5K-entry array)
- LogSearchViewModel + LogSearchBarView + EnhancedLogView
- ReadinessViewModel + ReadinessTrackerView
- WorktreeSwitchViewModel + WorktreeSwitchView + WorktreeMappingRow
- ViewModel tests (~33 tests)

### Modified Files
- miniDockerUIApp.swift — shared LogRingBuffer creation
- AppViewModel.swift — logBuffer property
- ContainerDetailViewModel.swift — ring buffer integration, 30 Hz throttled display
- ContentView.swift — logBuffer passthrough
- ContainerDetailView.swift — readiness tab, enhanced log view

### New Files (8 source + 5 test)
- Features/Logs/ViewModels/LogSearchViewModel.swift
- Features/Logs/Views/LogSearchBarView.swift
- Features/Logs/Views/EnhancedLogView.swift
- Features/Readiness/ViewModels/ReadinessViewModel.swift
- Features/Readiness/Views/ReadinessTrackerView.swift
- Features/Worktrees/ViewModels/WorktreeSwitchViewModel.swift
- Features/Worktrees/Views/WorktreeSwitchView.swift
- Features/Worktrees/Views/WorktreeMappingRow.swift

---

## W5-BUILD-TEST-HARNESS-003: Advanced Scenario Test Suite

**Status:** In Progress
**Lane:** Test

### Deliverables
- ScenarioTestHelpers + LogEntryFactory
- LogLoadGenerator implementation
- Log burst/search scenarios (12 tests)
- Stream disconnect/recovery scenarios (12 tests)
- Worktree switch/readiness scenarios (16 tests)
- Total: ~40 new integration tests

### New Files (8 test files)
- tests/Integration/Scenarios/ScenarioTestHelpers.swift
- tests/Integration/Scenarios/Logs/DockerLogLoadGenerator.swift
- tests/Integration/Scenarios/Logs/LogBurstIntegrationTests.swift (7 tests)
- tests/Integration/Scenarios/Logs/LogStreamSearchTests.swift (5 tests)
- tests/Integration/Scenarios/Recovery/StreamDisconnectRecoveryTests.swift (7 tests)
- tests/Integration/Scenarios/Recovery/StateResyncAfterGapTests.swift (5 tests)
- tests/Integration/Scenarios/Worktrees/WorktreeSwitchIntegrationTests.swift (8 tests)
- tests/Integration/Scenarios/Worktrees/WorktreeReadinessVerificationTests.swift (8 tests)
