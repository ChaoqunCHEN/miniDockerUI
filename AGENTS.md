# agents.md — Instructions for Codex Agents

## 🧠 Purpose
Agents exist to incrementally build the Docker-UX macOS application.

## 📘 How Agents Should Behave

### ❗ Always:
- Read the **./docs/highlevel_design.md** to understand the project archetecture.
- Read the **./docs/execution_plan.md** and pick a task for execution. Update the doc once task completed. 
- Use **./docs/execution_plan.md** for coordination with other agents. 
- Before starting any feature/task, plan it, and write plan into **./docs/features/** as a new md file with name using date and feature/task name. Keep the file updated with implementation status.
- Read files under ./docs/features to understand other features design and status for better coding. 
- Log new insights in **./docs/learnings.md**.
- Tag commits meaningfully: `feat/docker-core`, `fix/log-streaming`, `ui/log-filter`.

### 📂 Directory Structure
- `/app` → UI + runtime logic
- `/core` → Docker API abstraction
- `/agents` → agent config files
- `/docs` → docs + architecture

### 🛠 Task Execution
Agents should:
1. Claim a task from the execution plan.
2. Plan the task, and persists plan in ./docs/features as a new file
3. Generate code + tests + docs.
4. Run `make autoformat` after coding changes.
5. Validate with `make build` and `make tests` (and `make e2e-tests` when integration coverage is required).
6. **When adding new Swift files under `/app/Sources/miniDockerUIApp/`**, update `app/miniDockerUI.xcodeproj/project.pbxproj` to register them (PBXFileReference, PBXBuildFile, PBXGroup entries). SwiftPM auto-discovers files but the Xcode project has a static file list. Verify with `xcodebuild -project app/miniDockerUI.xcodeproj -scheme miniDockerUI -destination 'platform=macOS,arch=arm64' build`.
7. Run static analysis.
8. Update execution plan, feature doc.

**Do NOT commit or create PRs.** Leave changes for the user to review and commit manually.

### 📝 Reporting
After each task, agents write to:
- `./docs/project_status.md`: `{ task_id, status, timestamp, notes }`
- `learnings.md`: insights, blockers, docs improvements

### 🧹 Quality Standards
- Code must have **unit tests**.
- UI should follow **macOS Human Interface Guidelines**.
- Errors should be handled gracefully.

### 🔍 Post-Feature Quality Gates
After each feature/task is implemented and tests pass, run these checks before committing:
1. **Code quality** — Use the `coding-standards` skill to audit changed code for Swift best practices, naming, and maintainability.
2. **Code simplification** — Use the `code-simplifier` agent to refine recently modified code for clarity and consistency while preserving functionality.
3. **Fix issues** from above, then re-run `make build` and `make tests`.
4. Run `make autoformat` one final time.

### 🏁 Post-Wave Quality Gates
When all tasks in a wave are complete, the main agent must run these additional checks:
1. **Code review** — Use the `code-review` skill (`/code-review`) to review all changes in the wave (PR or diff against base branch). Address any issues with confidence >= 80.
2. **Code simplification** — Use the `code-simplifier` agent on all code modified during the wave for a final pass.
3. Re-run `make build`, `make tests`, and `make autoformat` after all fixes.
4. Verify all wave gate criteria in `./docs/execution_plan.md` are satisfied before proceeding to the next wave.

### Coding practice

- After feature completion, always look for refactoring opportunities to improve code clarity, readability, and re-usability.
- Modularize code as much as possible.
- Whenever fixing error, bug, do not fix it by adding bandaid, but proactively look into architecture flaws and improve it. Fix the root cause from first principle.
- Use context7 MCP server for reading the latest docker API/CLI documentations
