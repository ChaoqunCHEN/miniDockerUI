---
name: wave-task
description: Claim and execute a task from the execution plan following the wave-gated workflow
---

Follow this workflow to claim and execute the next task from the miniDockerUI execution plan.

## Workflow

### Phase 1: Plan & Implement

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

### Phase 2: Post-Feature Quality Gates

After the feature is implemented and tests pass, run these quality checks before committing:

11. **Code quality check** — Use the `coding-standards` skill to audit the changed code for Swift best practices, naming conventions, and maintainability
12. **Code simplification** — Use the `code-simplifier` agent (via Task tool with `subagent_type: "code-simplifier"`) to simplify and refine the recently modified code for clarity and consistency while preserving functionality
13. **Fix any issues** found by the quality check and simplifier, then re-run `make build` and `make tests` to confirm nothing broke
14. Run `make autoformat` one final time after all refinements

### Phase 3: Update Docs

15. Update `./docs/execution_plan.md` to mark the task as complete
16. Update `./docs/project_status.md` with `{ task_id, status, timestamp, notes }`
17. Update `./docs/learnings.md` with any new insights or patterns discovered

**Do NOT commit or create PRs.** Leave changes unstaged for the user to review.

### Phase 4: Wave Completion Gate

When ALL tasks in the current wave are marked complete:

18. **Code review** — Use the `code-review` skill to review uncommitted changes on the current branch (diff against base branch)
19. **Address review findings** — Fix any issues with confidence score >= 80 raised by the code review
20. Re-run `make build`, `make tests`, and `make autoformat` after fixes
21. Verify all wave gate criteria in `./docs/execution_plan.md` are satisfied before proceeding to the next wave

**Do NOT commit or create PRs.** Leave all changes for the user to review and commit manually.
