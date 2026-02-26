# Worktree-Aware Compose Recreation

**Date**: 2026-02-25
**Status**: Complete

## Overview

When using git worktrees, each worktree puts code in a different filesystem directory. Docker containers with bind mounts point to the host path they were created from. `docker restart` does NOT change volume mounts. This feature makes the Restart button worktree-aware: when a different worktree is selected in the UI, clicking Restart recreates the service via `docker compose up -d --force-recreate --no-deps <service>` from the new worktree directory.

## UX Flow

1. Sidebar toolbar shows a worktree picker auto-detected from compose container labels
2. User selects a different worktree for a compose project
3. User clicks Restart on a container
4. App detects the worktree change and does per-service compose recreation instead of simple restart
5. Container is recreated with volume mounts resolved from the new worktree directory

## Implementation Tasks

- [x] Core types: ComposeTypes.swift, GitTypes.swift, error cases
- [x] ComposeProjectDetector + tests (9 tests)
- [x] GitCLIAdapter + tests (12 tests)
- [x] CLIComposeAdapter + tests (9 tests)
- [x] ComposeWorktreeViewModel
- [x] Smart restart in AppViewModel
- [x] WorktreePickerView + sidebar integration
- [x] Dependency wiring + project.pbxproj
- [x] Build + test validation (375 tests, 0 failures)
