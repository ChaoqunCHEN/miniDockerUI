# Feature Plan: Wave 0 Build Contract Surface

## Metadata
- date: 2026-02-22
- task_id: W0-BUILD-CONTRACT-001
- status: completed

## Goal
Implement architecture contracts and types from `docs/highlevel_design.md` in core code:
1. runtime contracts (`EngineAdapter`, settings contract)
2. runtime models/types used by the contracts
3. public test contracts for integration harness architecture
4. compile-time/unit tests validating contract conformance and type expectations

## Planned Steps
1. Verify precondition `W0-BUILD-BOOT-001` via build/test evidence.
2. Create contract protocols under `core/Sources/MiniDockerCore/Contracts`.
3. Create architecture model types under `core/Sources/MiniDockerCore/Types`.
4. Add/extend unit tests under `core/Tests/MiniDockerCoreTests` for:
- protocol conformance and callable signatures
- codable/equatable model contract behavior
- public test-harness interface contracts
5. Run `swift build` and `swift test`.
6. Update plan/status/learnings documentation.

## Implementation Checklist
- [x] Precondition confirmed (`W0-BUILD-BOOT-001` completed from successful build/test evidence).
- [x] Added runtime contracts (`EngineAdapter`, `AppSettingsStore`).
- [x] Added public test contracts (`IntegrationEnvironmentProvider`, `EngineTestClient`, `FixtureOrchestrator`, `ReadinessProbeHarness`, `LogLoadGenerator`).
- [x] Added runtime types and JSON modeling (`RuntimeTypes`, `JSONValue`, test harness types).
- [x] Added contract/type unit tests under `core/Tests/MiniDockerCoreTests`.
- [x] Ran `swift build` successfully.
- [x] Ran `swift test` successfully.
- [x] Updated `docs/execution_plan.md`, `docs/project_status.md`, and `docs/learnings.md`.

## Notes
1. The branch already contained overlapping runtime type work; this task consolidated to one canonical type set in `RuntimeTypes.swift`.
2. Build/test commands required escalation in this runtime because SwiftPM invokes `sandbox-exec`.
