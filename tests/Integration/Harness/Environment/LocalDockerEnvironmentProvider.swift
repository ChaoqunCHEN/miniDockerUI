import Foundation
import MiniDockerCore

/// Concrete ``IntegrationEnvironmentProvider`` that targets the local Docker daemon
/// via the default Unix socket.
struct LocalDockerEnvironmentProvider: IntegrationEnvironmentProvider {
    private var isPrepared: Bool = false
    private let checker: any DockerAvailabilityChecking
    private let socketPath: String

    init(
        checker: any DockerAvailabilityChecking = DockerAvailabilityChecker(),
        socketPath: String = "/var/run/docker.sock"
    ) {
        self.checker = checker
        self.socketPath = socketPath
    }

    mutating func prepare() async throws {
        guard checker.binaryExists() else {
            throw CoreError.dependencyNotFound(
                name: "docker",
                searchedPaths: [
                    (checker as? DockerAvailabilityChecker)?.dockerPath ?? "/usr/local/bin/docker",
                ]
            )
        }

        let healthy = await checker.isDaemonHealthy()
        guard healthy else {
            throw CoreError.endpointUnreachable(
                endpoint: endpoint(),
                reason: "docker daemon is not responding"
            )
        }

        isPrepared = true
    }

    func endpoint() -> EngineEndpoint {
        EngineEndpoint(
            endpointType: .local,
            address: "unix://\(socketPath)"
        )
    }

    mutating func teardown() async {
        // For MVP: no artifacts to clean up — just reset state.
        isPrepared = false
    }
}
