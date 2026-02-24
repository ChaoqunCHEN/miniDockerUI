---
name: wave-task
description: Claim and execute a task from the execution plan following the wave-gated workflow
---

Follow this workflow to claim and execute the next task from the miniDockerUI execution plan.

## Workflow

1. Read `./docs/execution_plan.md` and identify the next unclaimed task in the current wave
2. Read `./docs/highlevel_design.md` for architecture context
3. Read existing feature docs in `./docs/features/` for related work and patterns
4. Create a new feature doc: `./docs/features/YYYY-MM-DD-<task-name>.md` with the implementation plan
5. Implement the code + unit tests following patterns in existing code
6. Run `make autoformat` to format all changed files
7. Run `make build` — fix any compilation errors
8. Run `make tests` — fix any test failures
9. Run `make e2e-tests` if the task requires integration coverage
10. If adding new Swift files under `/app/Sources/miniDockerUIApp/`, update `app/miniDockerUI.xcodeproj/project.pbxproj` to register them (PBXFileReference, PBXBuildFile, PBXGroup entries)
11. Commit with a meaningful tag prefix (feat/, fix/, ui/, test/, refactor/)
12. Update `./docs/execution_plan.md` to mark the task as complete
13. Update `./docs/project_status.md` with `{ task_id, status, timestamp, notes }`
14. Update `./docs/learnings.md` with any new insights or patterns discovered
