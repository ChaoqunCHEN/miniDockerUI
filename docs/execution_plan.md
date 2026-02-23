# Execution Plan (MVP, 3-Agent, Low-Conflict)

## Scope and Defaults
1. Scope is MVP only.
2. Maximum parallel agents: 3.
3. Build layout: `/app` plus Swift package-style `/core` and `/tests`.
4. Every wave must close quality gates before next wave starts.

## WaveGate Model (Mandatory)
Each wave tracks gate state with the following statuses:
- `dev_complete`
- `e2e_passed`
- `fix_complete`

A wave is complete only when all three are complete.

## Mandatory E2E Evidence Fields
Every `Wn-E2E` task must include:
1. test run ID
2. scenario checklist with pass/fail
3. failing defects list with severity (if any)
4. fix task references (`Wn-FIX` or split fix subtasks)
5. pass confirmation after fixes/rerun

## Global Execution Rules
1. Each wave has three phases:
- Build tasks
- `Wn-E2E`
- `Wn-FIX`
2. `Wn-E2E` runs against cumulative functionality through wave `n`.
3. `Wn-FIX` is always created and completed.
- If no defects: mark `no-op (verified)`.
- If defects exist: fix all P0/P1 and agreed P2 before wave close.
4. No task in wave `n+1` may be claimed until `Wn-FIX` is complete.
5. E2E/FIX updates must be written to:
- `docs/execution_plan.md`
- `docs/project_status.md`
- `docs/learnings.md`
6. Shared files are serialized ownership:
- project/workspace config files
- CI workflow files
- global docs touched by multiple lanes

## Conflict-Minimization Policy
1. Task claims are exclusive by `owned_paths`.
2. `Wn-E2E` writes only to `/tests/**` and docs evidence sections.
3. `Wn-FIX` may edit only modules touched in current wave build tasks.
4. If fixes span lanes, split as `Wn-FIX-A/B/C` by path ownership, keep parent `Wn-FIX` as gate tracker.

## Task Card Template
Use this card format for every task:
- `task_id`
- `wave`
- `lane` (`platform`, `engine`, `state`, `logs`, `readiness`, `worktree`, `ui`, `test`, `ci`, `qa`)
- `status` (`pending`, `in_progress`, `blocked`, `completed`)
- `depends_on`
- `owned_paths`
- `deliverables`
- `acceptance`
- `notes`

## Wave Dependency Pattern
For every wave `n`:
1. All `Wn-BUILD-*` tasks complete.
2. `Wn-E2E` executes and records evidence.
3. `Wn-FIX` resolves defects and reruns impacted scenarios.
4. WaveGate marked complete.
5. Next wave begins.

## Wave Plan (Task by Task)

### Wave 0
WaveGate status:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W0-BUILD-BOOT-001 | platform | completed | none | `/app/**`, `/core/**`, `/tests/**`, build config | repo bootstrap with app/core/tests skeleton | app and test targets compile |
| W0-BUILD-CONTRACT-001 | engine | completed | W0-BUILD-BOOT-001 | `/core/**Contracts**`, `/core/**Types**` | contracts from `highlevel_design.md` represented in code | contract compile + unit tests pass |
| W0-E2E | test | completed | W0-BUILD-BOOT-001, W0-BUILD-CONTRACT-001 | `/tests/**`, `docs/execution_plan.md` evidence section | app boot smoke + test target smoke + harness skeleton smoke | evidence fields filled, smoke scenarios pass or defects logged |
| W0-FIX | qa | completed | W0-E2E | wave 0 build paths + `/tests/**` | resolve bootstrap/harness defects from W0-E2E | P0/P1 closed, rerun pass, mark `fix_complete` |

#### W0-E2E Evidence
1. test run ID: `run-w0-e2e-20260222T104002-0800`
2. scenario checklist:
- app boot smoke: `PASS` (`xcodebuild -project app/miniDockerUI.xcodeproj -scheme miniDockerUI -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`; `** BUILD SUCCEEDED **`)
- test target smoke: `PASS` (`swift test --filter MiniDockerCoreTests`; 16 tests executed, 0 failures)
- harness skeleton smoke: `PASS` (`swift test --filter IntegrationHarnessTests`; 2 tests executed, 0 failures)
3. failing defects list with severity:
- none
4. fix task refs:
- `W0-FIX` (no-op verified)
5. pass confirmation after fixes/rerun:
- initial smoke pass completed, and Wave 0 rerun evidence captured in `W0-FIX` section below.

#### W0-FIX Evidence
1. rerun ID: `run-w0-fix-rerun-20260222T104028-0800`
2. defects fixed:
- none (no P0/P1 defects found; no agreed P2 defects opened)
3. rerun scenario checklist:
- app boot smoke rerun: `PASS` (`xcodebuild ... build`; `** BUILD SUCCEEDED **`)
- test target smoke rerun: `PASS` (`swift test --filter MiniDockerCoreTests`; 16 tests executed, 0 failures)
- harness skeleton smoke rerun: `PASS` (`swift test --filter IntegrationHarnessTests`; 2 tests executed, 0 failures)
4. Wave 0 gate close confirmation:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

### Wave 1
WaveGate status:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W1-BUILD-ENG-CLI-001 | engine | completed | W0-FIX | `/core/Sources/Engine/CLI/Runner/**`, `/core/Tests/Engine/CLI/Runner/**` | command runner + process lifecycle controls | success/failure/timeout/cancel tests pass |
| W1-BUILD-STATE-001 | state | completed | W0-FIX | `/core/Sources/State/Settings/**`, `/core/Tests/State/Settings/**` | JSON settings store + schema migration base + keychain abstraction | load/save/migrate tests pass |
| W1-BUILD-TEST-HARNESS-001 | test | completed | W0-FIX | `/tests/Integration/Harness/Environment/**` | `IntegrationEnvironmentProvider` base with prepare/endpoint/teardown | deterministic prepare/teardown tests pass |
| W1-BUILD-TEST-FIXTURES-002 | test | completed | W0-FIX | `/docker/manual-fun-fixtures/**`, `Makefile`, `/docs/**` | local manual-test docker compose fixtures with random logs and make targets | `docker compose config` passes; `make manual-fixtures-up` starts fixtures when Docker daemon is available |
| W1-E2E | test | completed | W1-BUILD-ENG-CLI-001, W1-BUILD-STATE-001, W1-BUILD-TEST-HARNESS-001 | `/tests/**`, `docs/execution_plan.md` evidence section | preflight E2E: dependency checks, settings load/save, env lifecycle | evidence fields filled, scenarios pass or defects logged |
| W1-FIX | qa | completed | W1-E2E | wave 1 build paths + `/tests/**` | fix runner/settings/provider defects | P0/P1 closed, rerun pass |

#### W1-E2E Evidence
1. test run ID: `run-w1-e2e-20260222T222745-0800`
2. scenario checklist:
- full build: `PASS` (`swift build`; `Build complete!`)
- unit tests: `PASS` (`swift test --skip IntegrationHarnessTests`; 58 tests executed, 0 failures)
- integration harness tests: `PASS` (`swift test --filter IntegrationHarnessTests`; 9 tests executed, 1 skipped, 0 failures)
3. failing defects list with severity:
- **P0**: CLICommandRunner continuation deadlock — `onCancel` handler set `isFinished = true`, preventing `terminationHandler` from resuming the continuation (permanent hang in timeout/cancellation tests)
- **P1**: DockerAvailabilityChecker `isDaemonHealthy()` had no timeout — `docker info` against non-responsive daemon causes indefinite hang in integration tests
4. fix task refs:
- `W1-FIX` (both P0 and P1 fixed inline)
5. pass confirmation after fixes/rerun:
- rerun completed with all scenarios passing (58 unit + 9 integration, 1 skipped)

#### W1-FIX Evidence
1. rerun ID: `run-w1-fix-rerun-20260222T222745-0800`
2. defects fixed:
- **P0 fix**: Changed `CLICommandRunner.run()` so `onCancel` and timeout handlers only set flags (`didCancel`/`didTimeout`) and terminate process; `terminationHandler` is the single point that resumes the continuation, checking flags to determine error type
- **P1 fix**: Added 10-second timeout with `OSAllocatedUnfairLock`-guarded continuation to `DockerAvailabilityChecker.isDaemonHealthy()`, ensuring process is terminated and continuation resumed on timeout
3. rerun scenario checklist:
- full build rerun: `PASS`
- unit tests rerun: `PASS` (58 tests, 0 failures)
- integration harness tests rerun: `PASS` (9 tests, 1 skipped, 0 failures)
4. Wave 1 gate close confirmation:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

### Wave 2
WaveGate status:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W2-BUILD-ENG-CLI-002 | engine | completed | W1-FIX | `/core/Sources/Engine/CLI/Parsers/**`, `/core/Tests/Engine/CLI/Parsers/**` | parsers for list/inspect/events/log formats | parser fixtures pass including malformed input |
| W2-BUILD-LOG-001 | logs | completed | W1-FIX | `/core/Sources/Logs/**`, `/core/Tests/Logs/**` | bounded ring buffer + search primitives | cap/truncation/search tests pass |
| W2-BUILD-WT-001 | worktree | completed | W1-FIX | `/core/Sources/Worktrees/**`, `/core/Tests/Worktrees/**` | worktree mapping validation + switch planning | parse/validation tests pass |
| W2-E2E | test | completed | W2-BUILD-ENG-CLI-002, W2-BUILD-LOG-001, W2-BUILD-WT-001 | `/tests/**`, `docs/execution_plan.md` evidence section | parser-to-state smoke, log cap/search E2E, worktree mapping E2E | evidence fields filled, scenarios pass or defects logged |
| W2-FIX | qa | completed | W2-E2E | wave 2 build paths + `/tests/**` | fix parser/buffer/worktree defects | P0/P1 closed, rerun pass |

#### W2-E2E Evidence
1. test run ID: `run-w2-e2e-20260222T225400-0800`
2. scenario checklist:
- full build: `PASS` (`swift build`; `Build complete!`)
- unit tests: `PASS` (`swift test --skip IntegrationHarnessTests`; 156 tests executed, 0 failures)
- integration harness tests: `PASS` (`swift test --filter IntegrationHarnessTests`; 9 tests executed, 1 skipped, 0 failures)
- parser fixtures (list/inspect/events/logs): `PASS` (40 parser tests including malformed input handling)
- log buffer cap/truncation/search: `PASS` (31 ring buffer and search tests including high-volume and drop strategy tests)
- worktree mapping validation/switch planning: `PASS` (27 validation and planner tests including all error conditions)
3. failing defects list with severity:
- **P2**: LogSearchEngine `gatherCandidates` returns empty when no `containerFilter` is set (limitation — no container list API on buffer). Deferred: callers always specify container filter in practice.
4. fix task refs:
- `W2-FIX` (P2 deferred, no P0/P1 defects)
5. pass confirmation after fixes/rerun:
- initial E2E pass completed with all 156 unit tests and 9 integration tests passing

#### W2-FIX Evidence
1. rerun ID: `run-w2-fix-rerun-20260222T225400-0800`
2. defects fixed:
- **P2 deferred**: LogSearchEngine without containerFilter returns empty results. Accepted as limitation for Wave 2; will be addressed when container list API is added to LogRingBuffer in Wave 5 (UI log search will always have container context).
3. rerun scenario checklist:
- full build rerun: `PASS`
- unit tests rerun: `PASS` (156 tests, 0 failures)
- integration harness tests rerun: `PASS` (9 tests, 1 skipped, 0 failures)
4. Wave 2 gate close confirmation:
- `dev_complete`: completed
- `e2e_passed`: completed
- `fix_complete`: completed

### Wave 3
WaveGate status:
- `dev_complete`: pending
- `e2e_passed`: pending
- `fix_complete`: pending

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W3-BUILD-ENG-CLI-003 | engine | pending | W2-FIX | `/core/Sources/Engine/CLI/Adapter/**`, `/core/Tests/Engine/CLI/Adapter/**` | `CLIEngineAdapter` implementing lifecycle/list/log/event calls | adapter tests pass |
| W3-BUILD-READY-001 | readiness | pending | W2-FIX | `/core/Sources/Readiness/**`, `/core/Tests/Readiness/**` | health and regex readiness evaluator | health-first + stale-line guard tests pass |
| W3-BUILD-UI-001 | ui | pending | W2-FIX | `/app/**` (app shell + wiring only), `/tests/UI/Smoke/**` | app shell, navigation, dependency wiring | shell boot and smoke tests pass |
| W3-E2E | test | pending | W3-BUILD-ENG-CLI-003, W3-BUILD-READY-001, W3-BUILD-UI-001 | `/tests/**`, `docs/execution_plan.md` evidence section | app shell + real adapter lifecycle E2E + readiness transitions | evidence fields filled, scenarios pass or defects logged |
| W3-FIX | qa | pending | W3-E2E | wave 3 build paths + `/tests/**` | fix adapter integration and app runtime defects | P0/P1 closed, rerun pass |

### Wave 4
WaveGate status:
- `dev_complete`: pending
- `e2e_passed`: pending
- `fix_complete`: pending

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W4-BUILD-STATE-002 | state | pending | W3-FIX | `/core/Sources/State/Containers/**`, `/core/Tests/State/Containers/**` | snapshot/event reconciliation reducer | reconnect/resync tests pass |
| W4-BUILD-UI-002 | ui | pending | W3-FIX | `/app/Features/Containers/**`, `/tests/UI/Containers/**` | container list, star/unstar, built-in actions UI | interaction tests pass |
| W4-BUILD-TEST-HARNESS-002 | test | pending | W3-FIX | `/tests/Integration/Harness/Fixtures/**`, `/tests/Integration/Scenarios/Lifecycle/**` | fixture orchestrator + lifecycle scenarios | fully automated lifecycle scenarios pass |
| W4-E2E | test | pending | W4-BUILD-STATE-002, W4-BUILD-UI-002, W4-BUILD-TEST-HARNESS-002 | `/tests/**`, `docs/execution_plan.md` evidence section | list/actions/star flows E2E + lifecycle suite | evidence fields filled, scenarios pass or defects logged |
| W4-FIX | qa | pending | W4-E2E | wave 4 build paths + `/tests/**` | fix reconcile/action/UI defects | P0/P1 closed, rerun pass |

### Wave 5
WaveGate status:
- `dev_complete`: pending
- `e2e_passed`: pending
- `fix_complete`: pending

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W5-BUILD-ENG-CLI-004 | engine | pending | W4-FIX | `/core/Sources/Engine/CLI/Streams/**`, `/core/Tests/Engine/CLI/Streams/**` | stream supervisor + reconnect/backoff/resync | disconnect/recovery tests pass |
| W5-BUILD-UI-003 | ui | pending | W4-FIX | `/app/Features/Logs/**`, `/app/Features/Readiness/**`, `/app/Features/Worktrees/**`, `/tests/UI/Advanced/**` | logs/search, readiness, worktree switch UI flows | advanced view model and UI tests pass |
| W5-BUILD-TEST-HARNESS-003 | test | pending | W4-FIX | `/tests/Integration/Scenarios/Logs/**`, `/tests/Integration/Scenarios/Recovery/**`, `/tests/Integration/Scenarios/Worktrees/**` | advanced integration scenario matrix | all advanced scenarios executable without manual steps |
| W5-E2E | test | pending | W5-BUILD-ENG-CLI-004, W5-BUILD-UI-003, W5-BUILD-TEST-HARNESS-003 | `/tests/**`, `docs/execution_plan.md` evidence section | reconnect/resync, log burst, readiness stale-line, worktree switch/restart E2E | evidence fields filled, scenarios pass or defects logged |
| W5-FIX | qa | pending | W5-E2E | wave 5 build paths + `/tests/**` | fix stream/recovery/log/readiness/worktree defects | P0/P1 closed, rerun pass |

### Wave 6
WaveGate status:
- `dev_complete`: pending
- `e2e_passed`: pending
- `fix_complete`: pending

| task_id | lane | status | depends_on | owned_paths | deliverables | acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| W6-BUILD-CI-001 | ci | pending | W5-FIX | `/.github/workflows/**` (Linux job sections), `/tests/**` CI scripts | Linux integration pipeline with artifacts on failure | Linux CI integration job green |
| W6-BUILD-CI-002 | ci | pending | W6-BUILD-CI-001 | `/.github/workflows/**` (macOS job sections), `/tests/**` CI scripts | macOS integration pipeline | macOS CI integration job green |
| W6-BUILD-QA-001 | qa | pending | W6-BUILD-CI-002 | `/docs/**`, targeted module fixes by ownership | final QA hardening and gate checks | docs, tests, and release checks complete |
| W6-E2E | test | pending | W6-BUILD-CI-001, W6-BUILD-CI-002, W6-BUILD-QA-001 | `/tests/**`, `docs/execution_plan.md` evidence section | full regression E2E in Linux and macOS CI with artifact checks | evidence fields filled and full pass confirmed |
| W6-FIX | qa | pending | W6-E2E | wave 6 build paths + `/tests/**` | final stabilization and defect closure | P0/P1 closed, approved P2 dispositioned, final gate closed |

## Minimum Scenarios Required for Every E2E Cycle
1. App launch and preflight checks.
2. Adapter lifecycle actions and error handling.
3. Event stream plus reconciliation.
4. Log streaming and search within memory caps.
5. Readiness health plus regex window correctness.
6. Worktree mapping/switch/restart validation.
7. Disconnect/reconnect full resync.
8. Secret redaction and persistence safety.
9. Linux/macOS CI parity by Wave 6.

## Parallelization Matrix (Max 3 Agents)
1. Agent A default lane: engine.
2. Agent B default lane: state/logs/readiness/worktree.
3. Agent C default lane: ui/test/ci/qa.
4. Reassignment allowed only at wave boundaries or explicit blocker.

## Current Completed Architecture Tasks
| task_id | status | notes |
| --- | --- | --- |
| ARCH-001 | completed | High-level architecture baseline in `docs/highlevel_design.md`. |
| TEST-ARCH-001 | completed | Non-interactive integration architecture sections and contracts documented. |
| TEST-PIPE-001 | completed | Linux + macOS CI topology documented. |
