.PHONY: autoformat build run clean tests e2e-tests manual-fixtures-up manual-fixtures-down manual-fixtures-logs

SWIFT ?= swift
APP_PRODUCT := miniDockerUIApp
FORMAT_PATHS := Package.swift app core tests

autoformat:
	@if ! command -v swiftformat >/dev/null 2>&1; then \
		echo "swiftformat is not installed. Install with: brew install swiftformat"; \
		exit 1; \
	fi
	swiftformat $(FORMAT_PATHS)

build:
	$(SWIFT) build

run:
	$(SWIFT) run $(APP_PRODUCT)

clean:
	$(SWIFT) package clean

tests:
	$(SWIFT) test --skip IntegrationHarnessTests

e2e-tests:
	$(SWIFT) test --filter IntegrationHarnessTests

manual-fixtures-up:
	docker compose -f docker/manual-fun-fixtures/compose.yaml up -d

manual-fixtures-down:
	docker compose -f docker/manual-fun-fixtures/compose.yaml down --remove-orphans

manual-fixtures-logs:
	docker compose -f docker/manual-fun-fixtures/compose.yaml logs -f --tail=100
