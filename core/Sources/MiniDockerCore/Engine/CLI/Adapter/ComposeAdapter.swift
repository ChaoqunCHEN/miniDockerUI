import Foundation

/// Protocol for Docker Compose operations.
public protocol ComposeExecutor: Sendable {
    /// Recreate a single service using `docker compose up -d --force-recreate --no-deps <service>`.
    func recreateService(
        projectName: String,
        projectDirectory: String,
        configFiles: [String],
        serviceName: String,
        timeoutSeconds: Double?
    ) async throws
}

/// Implements ``ComposeExecutor`` by delegating to the Docker CLI's `compose` subcommand.
public struct CLIComposeAdapter: ComposeExecutor, Sendable {
    private let runner: any CommandRunning
    private let dockerPath: String

    /// Default timeout for recreate commands (seconds).
    private let defaultRecreateTimeout: Double = 120

    public init(
        dockerPath: String = "/usr/local/bin/docker",
        runner: any CommandRunning = CLICommandRunner()
    ) {
        self.dockerPath = dockerPath
        self.runner = runner
    }

    // MARK: - ComposeExecutor

    public func recreateService(
        projectName: String,
        projectDirectory: String,
        configFiles: [String],
        serviceName: String,
        timeoutSeconds: Double?
    ) async throws {
        var args = ["compose", "-p", projectName, "--project-directory", projectDirectory]
        for file in configFiles {
            args.append(contentsOf: ["-f", file])
        }
        args.append(contentsOf: ["up", "-d", "--force-recreate", "--no-deps", serviceName])

        let timeout = timeoutSeconds ?? defaultRecreateTimeout
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: args,
            timeoutSeconds: timeout
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw CoreError.composeRecreationFailed(
                projectName: projectName,
                service: serviceName,
                stderr: result.stderrString
            )
        }
    }

    // MARK: - Utilities

    /// Validate that the compose configuration is valid in the given directory.
    ///
    /// Not part of the ``ComposeExecutor`` protocol — kept as a convenience
    /// method on the concrete adapter for diagnostics and testing.
    public func validateConfigExists(
        projectDirectory: String,
        configFiles: [String]
    ) async throws -> Bool {
        var args = ["compose", "--project-directory", projectDirectory]
        for file in configFiles {
            args.append(contentsOf: ["-f", file])
        }
        args.append(contentsOf: ["config", "--quiet"])

        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: args,
            timeoutSeconds: 30
        )
        let result = try await runner.run(request)
        return result.isSuccess
    }
}
