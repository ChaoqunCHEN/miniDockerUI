# miniDockerUI

A lightweight native macOS Docker UI focused on core developer workflows.

## Status
Early development (MVP in progress).

## What this project is
- Native macOS app (SwiftUI + AppKit where needed)
- UI/control layer for an existing Docker Engine
- Designed for small footprint and clear developer workflows

## What this project is not
- Not a Docker runtime or VM replacement
- Not a Kubernetes platform

## Repository layout
- `app/` macOS app source and Xcode project
- `core/` shared core domain/runtime code (`MiniDockerCore`)
- `tests/Integration/` non-interactive integration harness bootstrap
- `docs/` architecture, execution plan, and project notes

## Development environment setup
### Prerequisites
- macOS 14+
- Xcode + Command Line Tools (matching versions)
- Swift toolchain compatible with your installed macOS SDK
- Docker CLI available in `PATH`
- Git

### Setup steps
1. Clone the repo:
```bash
git clone https://github.com/chaoqunc/miniDockerUI.git
cd miniDockerUI
```
2. Verify toolchain:
```bash
swift --version
xcodebuild -version
docker --version
git --version
```

## Run in development
### Option A: Xcode
1. Open `app/miniDockerUI.xcodeproj` in Xcode.
2. Select the `miniDockerUI` scheme.
3. Press Run.

### Option B: Swift Package Manager
```bash
swift run miniDockerUIApp
```

## Testing
Run all tests:
```bash
swift test
```

Run integration harness tests only:
```bash
swift test --filter IntegrationHarnessTests
```

## Install
Current install method is from source build.

1. Build release binary:
```bash
swift build -c release
```
2. Run the built app executable:
```bash
./.build/release/miniDockerUIApp
```

Packaged installer/app bundle distribution is not available yet.

## Documentation
- Architecture: `docs/highlevel_design.md`
- Execution plan: `docs/execution_plan.md`

## License
MIT. See `LICENSE`.
