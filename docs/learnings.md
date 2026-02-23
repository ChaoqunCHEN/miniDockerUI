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

## 2026-02-22 (manual docker log fixtures)
1. Hosting manual-test containers in an isolated Compose directory with bind-mounted scripts keeps fixture behavior editable without image rebuilds.
2. `docker compose config` is a fast validation gate for fixture syntax and mount resolution even when the Docker daemon is unavailable.
3. For manual log-view testing, randomized but structured key-value log lines (for example `latency_ms=`, `bpm=`, `event=`) are more useful than plain free-text spam because they exercise both readability and parsing/search scenarios.
