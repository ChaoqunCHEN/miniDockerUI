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
