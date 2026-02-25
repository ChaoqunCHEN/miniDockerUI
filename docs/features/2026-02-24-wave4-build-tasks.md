# Wave 4 Build Tasks — Feature Plan

## Date: 2026-02-24
## Status: All 3 build tasks completed

---

## W4-BUILD-STATE-002: Container State Reconciliation

### Deliverables
- `ContainerSyncStatus` enum (idle, syncing, synced, disconnected, resyncRequired)
- `ContainerEvent` enum with `classify()` for Docker event action strings
- `ContainerState` immutable state model (container map + sync metadata)
- `ContainerStateReducer` pure-function reducer (applySnapshot, applyEvent, markDisconnected, applyResyncSnapshot, hasSequenceGap)
- `ReconcileAction` enum for caller signaling (none, resyncRequired, containerRemoved, ignored)
- `ContainerStateHolder` thread-safe wrapper using OSAllocatedUnfairLock

### Tests: 46 new unit tests
- ContainerStateTests (6 tests): state model construction, lookup, sorted list, equality
- ContainerEventTests (12 tests): event classification from action strings
- ContainerStateReducerTests (20 tests): snapshot apply, event apply, sequence gap detection, disconnect/reconnect
- ContainerStateHolderTests (8 tests): thread-safe read/write, concurrent access

### Files Created
- `core/Sources/MiniDockerCore/State/Containers/ContainerSyncStatus.swift`
- `core/Sources/MiniDockerCore/State/Containers/ContainerEvent.swift`
- `core/Sources/MiniDockerCore/State/Containers/ContainerState.swift`
- `core/Sources/MiniDockerCore/State/Containers/ContainerStateReducer.swift`
- `core/Sources/MiniDockerCore/State/Containers/ContainerStateHolder.swift`
- `core/Tests/MiniDockerCoreTests/State/Containers/ContainerStateTests.swift`
- `core/Tests/MiniDockerCoreTests/State/Containers/ContainerEventTests.swift`
- `core/Tests/MiniDockerCoreTests/State/Containers/ContainerStateReducerTests.swift`
- `core/Tests/MiniDockerCoreTests/State/Containers/ContainerStateHolderTests.swift`

---

## W4-BUILD-UI-002: Container List, Star/Unstar, Actions UI

### Deliverables
- `ContainerGrouper` pure grouping logic (Favorites/Running/Stopped sections)
- Star/unstar toggle persisted via AppSettingsStore
- Per-container action-in-progress indicators
- Context menu on container rows (start/stop/restart/star)
- UIContainerTests test target

### Tests: 12 new tests
- ContainerGroupingTests (7 tests): grouping with/without favorites, sort order, mixed states
- ContainerFavoritesTests (5 tests): key format, toggle, persistence round-trip

### Files Created
- `core/Sources/MiniDockerCore/Types/ContainerGrouping.swift`
- `app/Sources/miniDockerUIApp/Features/Containers/Views/ContainerContextMenu.swift`
- `tests/UI/Containers/MockSettingsStore.swift`
- `tests/UI/Containers/ContainerGroupingTests.swift`
- `tests/UI/Containers/ContainerFavoritesTests.swift`

### Files Modified
- `app/Sources/miniDockerUIApp/ViewModels/AppViewModel.swift` — added settingsStore, favorites, actionInProgress
- `app/Sources/miniDockerUIApp/Views/ContainerListView.swift` — favorites-aware grouping, context menus
- `app/Sources/miniDockerUIApp/Views/ContainerRowView.swift` — star icon, action spinner
- `app/Sources/miniDockerUIApp/miniDockerUIApp.swift` — JSONSettingsStore injection
- `Package.swift` — UIContainerTests test target
- `app/miniDockerUI.xcodeproj/project.pbxproj` — new file references

---

## W4-BUILD-TEST-HARNESS-002: Fixture Orchestrator & Lifecycle Scenarios

### Deliverables
- `DockerFixtureOrchestrator` implementing `FixtureOrchestrator` protocol
- `FixtureContainerState` enum for desired states
- 3 lifecycle scenario test suites (lifecycle, bootstrap, recovery)

### Tests: ~29 new tests (mock + real Docker)
- FixtureOrchestratorTests (10 tests): naming, arg verification, cleanup, real Docker
- ContainerLifecycleTests (9 tests): create/start/stop/restart lifecycle
- ContainerListBootstrapTests (6 tests): list snapshot, event reconciliation
- EventStreamRecoveryTests (4 tests): stream restart, resync, concurrent actions

### Files Created
- `tests/Integration/Harness/Fixtures/FixtureContainerState.swift`
- `tests/Integration/Harness/Fixtures/DockerFixtureOrchestrator.swift`
- `tests/Integration/Harness/Fixtures/FixtureOrchestratorTests.swift`
- `tests/Integration/Scenarios/Lifecycle/ContainerLifecycleTests.swift`
- `tests/Integration/Scenarios/Lifecycle/ContainerListBootstrapTests.swift`
- `tests/Integration/Scenarios/Lifecycle/EventStreamRecoveryTests.swift`

---

## Cumulative Test Results
- Unit tests: 281 (198 original + 46 STATE-002 + 25 existing misc + 12 UI-002)
- Integration harness tests: 26+ existing + new lifecycle scenarios (real Docker required)
- All tests passing, 0 failures
- `swift build`: PASS
- `xcodebuild`: BUILD SUCCEEDED
