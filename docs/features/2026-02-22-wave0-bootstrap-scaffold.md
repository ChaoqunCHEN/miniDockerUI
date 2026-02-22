# Feature Plan: Wave 0 Bootstrap Scaffold

## Metadata
- date: 2026-02-22
- task_id: W0-BUILD-BOOT-001
- status: blocked (verification environment issue)

## Goal
Create baseline repository scaffolding for implementation kickoff:
1. `.gitignore`
2. Swift package layout for `app`, `core`, and `tests`
3. minimal SwiftUI app target
4. Xcode project for local IDE workflow
5. minimal core module and starter tests

## Planned Steps
1. Add baseline ignore rules for macOS/Xcode/Swift artifacts.
2. Add root `Package.swift` with:
- library target `MiniDockerCore`
- executable target `miniDockerUIApp`
- unit and integration test targets
3. Add SwiftUI app bootstrap files under `app/Sources/miniDockerUIApp`.
4. Add Xcode project under `app/miniDockerUI.xcodeproj`.
5. Add core bootstrap module under `core/Sources/MiniDockerCore`.
6. Add starter tests under `core/Tests` and `tests/Integration`.
7. Run `swift build` and `swift test` for validation.

## Completed Work
- [x] Added `.gitignore`.
- [x] Added root `Package.swift`.
- [x] Added SwiftUI app bootstrap files.
- [x] Added Xcode project and shared scheme (`app/miniDockerUI.xcodeproj`).
- [x] Updated Xcode target structure to link local package product `MiniDockerCore` instead of compiling core files directly in app target.
- [x] Added core bootstrap source.
- [x] Added unit/integration harness starter tests.
- [x] Updated `README.md` quick-start and Xcode instructions.
- [ ] Validation commands pass (`swift build`, `swift test`) - blocked by local toolchain/sandbox mismatch.

## Validation Notes
`swift build` and `swift test` currently fail in this environment due:
1. cache/module write restrictions to user home cache directories in sandbox
2. Swift toolchain/SDK compatibility mismatch reported by compiler
3. full Xcode toolchain not selected (`xcodebuild` unavailable via current developer directory)
4. project syntax validated with `plutil`, but end-to-end Xcode build verification is still pending on a machine with full Xcode selected

## Follow-up
1. Re-run validation once toolchain/SDK alignment is fixed.
2. Move task from `blocked` to `completed` in `docs/execution_plan.md` after successful build/test.
