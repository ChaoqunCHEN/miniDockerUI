# Wave 3: CLIEngineAdapter + ReadinessEvaluator + App Shell

**Date**: 2026-02-23
**Status**: COMPLETE (all gates closed)

## Overview

Wave 3 bridges the foundational components (Waves 0-2) into a functional macOS app. Three parallel build tasks:

1. **CLIEngineAdapter** — Implements `EngineAdapter` protocol via Docker CLI
2. **ReadinessEvaluator** — Health/regex readiness evaluation
3. **App Shell** — SwiftUI navigation, container list, logs, inspect, actions

## CLIEngineAdapter (W3-BUILD-ENG-CLI-003)

### Design
- Sendable struct composing `CLICommandRunner` + all 4 parsers
- `CommandRunning` protocol extracted for testability (mock injection)
- `DataLineAccumulator` converts chunked `Data` streams into lines

### API Mapping
| Method | Docker Command |
|--------|---------------|
| `listContainers()` | `docker ps -a --format json --no-trunc` |
| `inspectContainer(id:)` | `docker inspect <id>` |
| `startContainer(id:)` | `docker start <id>` |
| `stopContainer(id:timeoutSeconds:)` | `docker stop [--time N] <id>` |
| `restartContainer(id:timeoutSeconds:)` | `docker restart [--time N] <id>` |
| `streamEvents(since:)` | `docker events --format json [--since N]` |
| `streamLogs(id:options:)` | `docker logs -t [-f] [--tail N] [--since T] <id>` |

### Files
- `core/Sources/MiniDockerCore/Engine/CLI/Runner/CommandRunning.swift`
- `core/Sources/MiniDockerCore/Engine/CLI/Adapter/CLIEngineAdapter.swift`
- `core/Sources/MiniDockerCore/Engine/CLI/Adapter/DataLineAccumulator.swift`
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Adapter/CLIEngineAdapterTests.swift`
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Adapter/DataLineAccumulatorTests.swift`

## ReadinessEvaluator (W3-BUILD-READY-001)

### Design
- Stateless, pure evaluator — takes observations + rule, returns result
- Three modes: `.healthOnly`, `.regexOnly`, `.healthThenRegex`
- Stale-line rejection via `windowStart` date filtering
- Throws `CoreError.contractViolation` on invalid regex

### Files
- `core/Sources/MiniDockerCore/Readiness/ReadinessEvaluator.swift`
- `core/Sources/MiniDockerCore/Readiness/ReadinessResult.swift`
- `core/Tests/MiniDockerCoreTests/Readiness/ReadinessEvaluatorTests.swift`

## App Shell (W3-BUILD-UI-001)

### Architecture
```
MiniDockerUIApp → AppViewModel (@Observable, @MainActor)
  └─ ContentView (NavigationSplitView)
       ├─ ContainerListView (sidebar, grouped running/stopped)
       │    └─ ContainerRowView
       └─ ContainerDetailView (tabs: logs/inspect + toolbar actions)
            ├─ ContainerLogView (live streaming, auto-scroll, monospaced)
            └─ ContainerInspectView (summary/network/mounts/health)
```

### Key Decisions
- `@Observable` + `@MainActor` ViewModels for modern SwiftUI
- `EngineAdapter` protocol extended with `Sendable` conformance
- Event stream auto-refreshes container list on Docker events
- Log entries capped at 5000 lines in-memory (pre-LogRingBuffer integration)
- `.id(selectedId)` on detail view forces recreation on container switch

### Files
- `app/Sources/miniDockerUIApp/ViewModels/AppViewModel.swift`
- `app/Sources/miniDockerUIApp/ViewModels/ContainerDetailViewModel.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerListView.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerRowView.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerDetailView.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerLogView.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerInspectView.swift`
- `app/Sources/miniDockerUIApp/Views/EmptyStateView.swift`
- `app/Sources/miniDockerUIApp/miniDockerUIApp.swift` (modified)
- `app/Sources/miniDockerUIApp/ContentView.swift` (modified)

## Test Coverage
- **198 total unit tests**, 0 failures
- New: 19 adapter tests, 11 accumulator tests, 15 readiness tests
- All 156 existing tests continue to pass
- **26 integration tests**, 0 failures, 0 skipped
- New: 9 adapter lifecycle scenario tests, 8 readiness integration tests

## Integration Scenario Tests (W3-E2E)

### Adapter Lifecycle (`tests/Integration/Scenarios/Adapter/CLIAdapterLifecycleTests.swift`)
- Multi-container NDJSON round-trip (3 containers)
- Full inspect detail with mounts, network, labels
- Start/stop/restart sequential lifecycle
- Error propagation (non-zero exit → CoreError)
- 12-event stream with sequence verification
- Chunked log delivery through DataLineAccumulator
- 6000-line no-cap verification (adapter does not limit)
- Real Docker: list containers (XCTSkip guarded)
- Real Docker: inspect known container (XCTSkip guarded)

### Readiness Integration (`tests/Integration/Scenarios/Readiness/ReadinessIntegrationTests.swift`)
- All ContainerHealthStatus variants
- Realistic log entries with regex matching
- 50-entry stale-line rejection (25 stale, 25 fresh)
- Health→regex fallback chain (healthy, starting, nil)
- mustMatchCount accumulation (3 of 4 entries match)
- Window start boundary is inclusive (timestamp == windowStart included)
- LogRingBuffer → ReadinessEvaluator cross-integration (100 entries)
- LogSearchEngine → ReadinessEvaluator cross-integration

## Verification
```bash
make manual-fixtures-up   # Start disco_bot + chaos_oracle
make run                  # Launch app — should list containers, stream logs
make manual-fixtures-down # Cleanup
```

## E2E Evidence
- Run ID: `run-w3-e2e-20260224T001951-0800`
- No defects found (W3-FIX: no-op verified)
- Wave 3 gate closed: all three gates completed
