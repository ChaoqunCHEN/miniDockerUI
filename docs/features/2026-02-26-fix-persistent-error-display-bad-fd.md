# Fix: Persistent Error Display & "Bad File Descriptor" Bug

**Date**: 2026-02-26
**Status**: completed

## Problem

1. "Bad file descriptor" errors appear briefly then auto-dismiss after 8 seconds, making diagnosis impossible.
2. All errors share a single `errorMessage: String?` property — errors overwrite each other.
3. Race condition in `CLICommandRunner` pipe handling: `readDataToEndOfFile()` on stderr can be called after the pipe's FD is invalidated.

## Root Cause

- **Pipe race in `run()`**: `readDataToEndOfFile()` was called inside the `terminationHandler`, which can execute after the pipe FD is invalidated by process cleanup.
- **Pipe race in `stream()`**: stderr was read after `process.waitUntilExit()`, same timing issue. Additionally, `Task.checkCancellation()` could throw without properly finishing the stream continuation.
- **Error UX**: Single `errorMessage: String?` with 8-second auto-dismiss meant critical Docker connectivity errors disappeared before users could read them.

## Solution

### 1. CLICommandRunner pipe fix (`run()`)
- Moved `readDataToEndOfFile()` calls to background `DispatchQueue` threads started *before* `process.run()`.
- Used `DispatchGroup` + `OSAllocatedUnfairLock` to synchronize.
- Termination handler waits for the group, then reads results from the lock.

### 2. CLICommandRunner pipe fix (`stream()`)
- Started stderr read on background thread immediately after `process.run()`.
- Wrapped the stdout while-loop in do/catch to properly handle `CancellationError`.
- Stored stdout `FileHandle` in `StreamProcessState` so `onTermination` can close it to unblock `availableData`.

### 3. Structured error model (`AppError`)
- Replaced `errorMessage: String?` with `currentError: AppError?`.
- `AppError` has `isPersistent: Bool` to control auto-dismiss behavior.
- Factory methods: `.transient()` for auto-dismissing, `.persistent()` for must-acknowledge.

### 4. ErrorBannerView enhancements
- Added `isPersistent` parameter — skips 8-second auto-dismiss timer when true.
- Added `onRetry` parameter — shows a "Retry" button when provided.
- Increased `lineLimit` from 2 to 3.
- Added `.textSelection(.enabled)` for copy-paste.

### 5. `refreshAndReconnect()` method
- Stops event stream, reloads containers, restarts event stream.
- Wired to: Retry button on error banner, Refresh toolbar button, initial `.task` on ContentView.

## Error Classification

| Call site | Type | Reason |
|-----------|------|--------|
| `loadContainers()` catch | persistent | Docker connectivity — user must see |
| `startEventStream()` max retries | persistent | Event stream dead — needs manual action |
| `startEventStream()` individual retry | transient | Auto-retrying |
| `performContainerAction()` catch | transient | Single action failure |
| `loadFavorites()` catch | transient | Non-critical |
| `saveFavorites()` catch | transient | Non-critical |

## Files Modified

- `core/Sources/MiniDockerCore/Engine/CLI/Runner/CLICommandRunner.swift`
- `app/Sources/miniDockerUIApp/Views/ErrorBannerView.swift`
- `app/Sources/miniDockerUIApp/ViewModels/AppViewModel.swift`
- `app/Sources/miniDockerUIApp/ContentView.swift`
- `app/Sources/miniDockerUIApp/Views/ContainerListView.swift`

## Verification

- `make build`: PASS
- `make tests`: 408 tests, 0 failures
- `make autoformat`: 0 files formatted
- Xcode build: BUILD SUCCEEDED
