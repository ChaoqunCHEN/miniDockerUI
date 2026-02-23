@preconcurrency import Dispatch
import Foundation
import MiniDockerCore
import os

/// Protocol for checking Docker availability without coupling to a specific implementation.
protocol DockerAvailabilityChecking: Sendable {
    func binaryExists() -> Bool
    func isDaemonHealthy() async -> Bool
}

/// Checks whether the Docker CLI binary is present and whether the Docker daemon is responding.
struct DockerAvailabilityChecker: DockerAvailabilityChecking, Sendable {
    let dockerPath: String

    init(dockerPath: String = "/usr/local/bin/docker") {
        self.dockerPath = dockerPath
    }

    func binaryExists() -> Bool {
        FileManager.default.isExecutableFile(atPath: dockerPath)
    }

    func isDaemonHealthy() async -> Bool {
        let path = dockerPath
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["info"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { finished in
                let shouldResume = resumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: finished.terminationStatus == 0)
                }
            }

            do {
                try process.run()
            } catch {
                let shouldResume = resumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: false)
                }
                return
            }

            // Timeout: kill the process after 10 seconds if it hasn't finished.
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                let shouldResume = resumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                if shouldResume {
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
