import Foundation
@testable import MiniDockerCore

/// Implements ``FixtureOrchestrator`` by delegating to the Docker CLI.
///
/// Creates, transitions, and removes fixture containers using the same
/// ``CommandRunning`` abstraction that ``CLIEngineAdapter`` uses. All
/// containers are named with the prefix `mdui-test-{runID}-{descriptorKey}`
/// for easy identification and bulk cleanup.
struct DockerFixtureOrchestrator: FixtureOrchestrator, Sendable {
    private let runner: any CommandRunning
    private let dockerPath: String
    private let defaultImage: String

    /// Default timeout for one-shot Docker commands (seconds).
    private let commandTimeout: Double = 30

    init(
        runner: any CommandRunning = CLICommandRunner(),
        dockerPath: String = "/usr/local/bin/docker",
        defaultImage: String = "alpine:3.20"
    ) {
        self.runner = runner
        self.dockerPath = dockerPath
        self.defaultImage = defaultImage
    }

    // MARK: - FixtureOrchestrator Protocol

    /// Creates fixture containers in the `created` state (docker create only).
    func createFixtures(
        runID: String,
        descriptors: [FixtureDescriptor]
    ) async throws -> [FixtureHandle] {
        let states = descriptors.map { _ in FixtureContainerState.created }
        return try await createFixtures(runID: runID, descriptors: descriptors, desiredStates: states)
    }

    // MARK: - Extended Method with State Transitions

    /// Creates fixture containers and transitions each to the desired state.
    ///
    /// - Parameters:
    ///   - runID: Unique run identifier for container naming.
    ///   - descriptors: Array of fixture descriptors defining image, command, environment.
    ///   - desiredStates: Parallel array of desired states (one per descriptor).
    /// - Returns: Array of ``FixtureHandle`` with container IDs.
    /// - Throws: If any creation or transition fails. On partial failure,
    ///           ``removeFixtures(runID:)`` is called for cleanup before rethrowing.
    func createFixtures(
        runID: String,
        descriptors: [FixtureDescriptor],
        desiredStates: [FixtureContainerState]
    ) async throws -> [FixtureHandle] {
        precondition(
            descriptors.count == desiredStates.count,
            "descriptors and desiredStates must have the same count"
        )

        var handles: [FixtureHandle] = []

        do {
            for (index, descriptor) in descriptors.enumerated() {
                let containerName = containerName(runID: runID, key: descriptor.key)
                let desiredState = desiredStates[index]

                // Step 1: docker create
                let image = descriptor.image.isEmpty ? defaultImage : descriptor.image
                var createArgs = ["create", "--name", containerName]

                // Add environment variables
                for (key, value) in descriptor.environment.sorted(by: { $0.key < $1.key }) {
                    createArgs.append(contentsOf: ["-e", "\(key)=\(value)"])
                }

                createArgs.append(image)
                createArgs.append(contentsOf: descriptor.command)

                let createRequest = CommandRequest(
                    executablePath: dockerPath,
                    arguments: createArgs,
                    timeoutSeconds: commandTimeout
                )
                let createResult = try await runner.run(createRequest)
                guard createResult.isSuccess else {
                    throw CoreError.processNonZeroExit(
                        executablePath: dockerPath,
                        exitCode: createResult.exitCode,
                        stderr: createResult.stderrString
                    )
                }

                // Step 2: Retrieve full container ID via docker inspect
                let inspectRequest = CommandRequest(
                    executablePath: dockerPath,
                    arguments: ["inspect", "--format", "{{.Id}}", containerName],
                    timeoutSeconds: commandTimeout
                )
                let inspectResult = try await runner.run(inspectRequest)
                guard inspectResult.isSuccess else {
                    throw CoreError.processNonZeroExit(
                        executablePath: dockerPath,
                        exitCode: inspectResult.exitCode,
                        stderr: inspectResult.stderrString
                    )
                }
                let containerId = inspectResult.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)

                // Step 3: Transition to desired state
                if desiredState == .running || desiredState == .stopped {
                    let startRequest = CommandRequest(
                        executablePath: dockerPath,
                        arguments: ["start", containerName],
                        timeoutSeconds: commandTimeout
                    )
                    let startResult = try await runner.run(startRequest)
                    guard startResult.isSuccess else {
                        throw CoreError.processNonZeroExit(
                            executablePath: dockerPath,
                            exitCode: startResult.exitCode,
                            stderr: startResult.stderrString
                        )
                    }
                }

                if desiredState == .stopped {
                    let stopRequest = CommandRequest(
                        executablePath: dockerPath,
                        arguments: ["stop", containerName],
                        timeoutSeconds: commandTimeout
                    )
                    let stopResult = try await runner.run(stopRequest)
                    guard stopResult.isSuccess else {
                        throw CoreError.processNonZeroExit(
                            executablePath: dockerPath,
                            exitCode: stopResult.exitCode,
                            stderr: stopResult.stderrString
                        )
                    }
                }

                handles.append(FixtureHandle(key: descriptor.key, containerId: containerId))
            }
        } catch {
            // Partial failure: clean up all containers from this run
            await removeFixtures(runID: runID)
            throw error
        }

        return handles
    }

    // MARK: - Cleanup

    /// Removes all containers whose names match the `mdui-test-{runID}-` prefix.
    ///
    /// This method is idempotent and **never throws**. Any errors from Docker
    /// (e.g. container already removed, daemon unreachable) are silently swallowed.
    func removeFixtures(runID: String) async {
        // List containers matching the run prefix
        let listRequest = CommandRequest(
            executablePath: dockerPath,
            arguments: [
                "ps", "-a",
                "--filter", "name=mdui-test-\(runID)",
                "--format", "{{.ID}}",
            ],
            timeoutSeconds: commandTimeout
        )

        let listResult: CommandResult
        do {
            listResult = try await runner.run(listRequest)
        } catch {
            return // Swallow errors
        }

        guard listResult.isSuccess else { return }

        let ids = listResult.stdoutString
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Remove each container forcefully
        for id in ids {
            let rmRequest = CommandRequest(
                executablePath: dockerPath,
                arguments: ["rm", "-f", id],
                timeoutSeconds: commandTimeout
            )
            do {
                _ = try await runner.run(rmRequest)
            } catch {
                // Swallow errors — removal is best-effort
            }
        }
    }

    // MARK: - Helpers

    /// Generates the standard container name for a fixture.
    func containerName(runID: String, key: String) -> String {
        "mdui-test-\(runID)-\(key)"
    }
}
