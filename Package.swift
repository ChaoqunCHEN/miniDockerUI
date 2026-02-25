// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "miniDockerUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MiniDockerCore",
            targets: ["MiniDockerCore"]
        ),
        .executable(
            name: "miniDockerUIApp",
            targets: ["miniDockerUIApp"]
        ),
    ],
    targets: [
        .target(
            name: "MiniDockerCore",
            path: "core/Sources/MiniDockerCore"
        ),
        .executableTarget(
            name: "miniDockerUIApp",
            dependencies: ["MiniDockerCore"],
            path: "app/Sources/miniDockerUIApp",
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "MiniDockerCoreTests",
            dependencies: ["MiniDockerCore"],
            path: "core/Tests/MiniDockerCoreTests"
        ),
        .testTarget(
            name: "IntegrationHarnessTests",
            dependencies: ["MiniDockerCore"],
            path: "tests/Integration",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "UIContainerTests",
            dependencies: ["MiniDockerCore"],
            path: "tests/UI/Containers"
        ),
        .testTarget(
            name: "UIAdvancedTests",
            dependencies: ["MiniDockerCore"],
            path: "tests/UI/Advanced"
        ),
    ]
)
