# Feature Plan: Manual Fun Docker Log Fixtures

## Metadata
- date: 2026-02-22
- task_id: W1-BUILD-TEST-FIXTURES-002
- status: completed

## Goal
Add two lightweight Docker containers that emit random, fun logs so manual app testing can validate:
1. container discovery and list rendering
2. live log streaming behavior
3. multi-container log switching

## Planned Steps
1. Create a dedicated fixture directory with a Compose stack and scripts.
2. Define two independent services that continuously print random log lines.
3. Add `Makefile` command(s) to start the fixture stack for manual testing.
4. Validate the compose config and run project quality checks.
5. Update execution/status/learnings docs with completion evidence.

## Checklist
- [x] Created dedicated fixture directory and compose file.
- [x] Added two random-log container services.
- [x] Added make target to start fixtures.
- [x] Validated compose config.
- [x] Ran required formatting/build/test checks.
- [x] Updated coordination docs (`execution_plan`, `project_status`, `learnings`).

## Deliverables
1. Added manual fixture stack under `docker/manual-fun-fixtures/compose.yaml`.
2. Added random log generator script `docker/manual-fun-fixtures/scripts/disco-bot.sh`.
3. Added random log generator script `docker/manual-fun-fixtures/scripts/chaos-oracle.sh`.
4. Added fixture usage guide `docker/manual-fun-fixtures/README.md`.
5. Added root make target `manual-fixtures-up`.
6. Added root make target `manual-fixtures-down`.
7. Added root make target `manual-fixtures-logs`.

## Verification
1. `sh -n docker/manual-fun-fixtures/scripts/disco-bot.sh` and `sh -n docker/manual-fun-fixtures/scripts/chaos-oracle.sh`: pass
2. `docker compose -f docker/manual-fun-fixtures/compose.yaml config`: pass
3. `make autoformat`: pass
4. `make build`: pass
5. `make tests`: pass
6. `make e2e-tests`: pass
7. `swift build -Xswiftc -warnings-as-errors`: pass
8. `make manual-fixtures-up`: blocked in this runtime because Docker daemon is not running (`Cannot connect to the Docker daemon ...docker.sock`)
