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
6. Run static analysis.
7. Commit code.
8. Update execution plan, feature doc.

### 📝 Reporting
After each commit, agents write to:
- `./docs/project_status.md`: `{ task_id, status, timestamp, notes }`
- `learnings.md`: insights, blockers, docs improvements

### 🧹 Quality Standards
- Code must have **unit tests**.
- UI should follow **macOS Human Interface Guidelines**.
- Errors should be handled gracefully.

### Coding practice

- After feature completion, always look for refactorying oppotunities to improve code clarity, readabiltiy, and re-useablitly.
- Modularize code as much as possible.
- Whenever fixing error, bug, do not fix it by adding bandit, but proactivily look into archetecture flaws and improve it. Fix the root cause from first principle. 
- Use context7 MCP server for reading the latest docker API/CLI documentations
