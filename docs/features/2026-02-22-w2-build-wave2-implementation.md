# Wave 2 Build Tasks Implementation

**Date**: 2026-02-22
**Tasks**: W2-BUILD-ENG-CLI-002, W2-BUILD-LOG-001, W2-BUILD-WT-001
**Status**: Complete

## W2-BUILD-ENG-CLI-002: CLI Parsers

### Deliverables
- `ContainerListParser` — Parses `docker ps --format json` (NDJSON) into `[ContainerSummary]`
- `ContainerInspectParser` — Parses `docker inspect` JSON array into `ContainerDetail`
- `EventStreamParser` — Parses `docker events --format json` lines into `EventEnvelope`
- `LogStreamParser` — Parses `docker logs -t` timestamped lines into `LogEntry`
- `DockerDateParser` — Internal shared date parsing (RFC3339Nano, Unix epoch, CLI format)

### Files
- `core/Sources/MiniDockerCore/Engine/CLI/Parsers/` (5 files)
- `core/Tests/MiniDockerCoreTests/Engine/CLI/Parsers/` (4 test files, ~40 tests)

### Design Decisions
- All parsers are stateless `Sendable` structs
- Uses `JSONSerialization` for flexible parsing (Docker JSON keys don't match Swift conventions)
- Health status extracted from parenthesized status string
- Labels parsed from comma-separated `key=value` format (split on first `=` only)
- Raw JSON preserved as `JSONValue` in inspect and events output

## W2-BUILD-LOG-001: Bounded Ring Buffer + Search

### Deliverables
- `LogRingBuffer` — Per-container circular buffer with line/byte caps
- `LogSearchQuery` / `LogSearchResult` — Search query and result types
- `LogSearchEngine` — Substring/regex/exact search over buffer contents

### Files
- `core/Sources/MiniDockerCore/Logs/` (3 files)
- `core/Tests/MiniDockerCoreTests/Logs/` (2 test files, ~31 tests)

### Design Decisions
- `final class LogRingBuffer: Sendable` with `OSAllocatedUnfairLock<State>` for thread safety
- Per-container `ContainerBuffer` with pre-allocated circular array
- Three drop strategies: `dropOldest` (evict oldest), `dropNewest` (reject new), `blockProducer` (same as dropNewest for Wave 2; actual blocking deferred to Wave 5 stream layer)
- Byte cost: `message.utf8.count + containerId.utf8.count + engineContextId.utf8.count + 64`
- Search takes snapshot via buffer's public API, matches outside lock

## W2-BUILD-WT-001: Worktree Mapping Validation + Switch Planning

### Deliverables
- `WorktreeValidationError` — Granular validation error enum
- `WorktreeMappingValidator` — Pure structural validation (no filesystem access)
- `WorktreeSwitchPlanner` — Pure switch plan generation with restart target computation

### Files
- `core/Sources/MiniDockerCore/Worktrees/` (3 files)
- `core/Tests/MiniDockerCoreTests/Worktrees/` (2 test files, ~27 tests)

### Design Decisions
- Separate `WorktreeValidationError` from `CoreError` for granular UI feedback
- Path normalization: strip trailing `/` before comparison
- Planner does NOT validate the mapping — only switch-specific parameters
- Restart targets: `.never`→[], `.always`→[targetId], `.ifRunning`→conditional on running state
- Readiness rule validation: regex mode requires pattern, mustMatchCount >= 1

## Test Results
- Build: PASS
- Unit tests: 156 tests, 0 failures (98 new + 58 existing)
- Integration harness: 9 tests, 1 skipped, 0 failures
