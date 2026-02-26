import Foundation

/// A Docker Compose project detected from container labels.
///
/// Extracted from `com.docker.compose.*` labels that Docker Compose
/// automatically applies to containers.
public struct ComposeProject: Sendable, Codable, Equatable {
    /// The compose project name (from `com.docker.compose.project` label).
    public let projectName: String

    /// The directory compose was originally run from
    /// (from `com.docker.compose.project.working_dir` label).
    public let workingDirectory: String

    /// Paths to compose config files used
    /// (from `com.docker.compose.project.config_files` label, comma-separated).
    public let configFiles: [String]

    /// Container IDs belonging to this project.
    public let containerIds: [String]

    /// Service names in this project
    /// (from `com.docker.compose.service` label per container).
    public let serviceNames: [String]

    public init(
        projectName: String,
        workingDirectory: String,
        configFiles: [String],
        containerIds: [String],
        serviceNames: [String]
    ) {
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.configFiles = configFiles
        self.containerIds = containerIds
        self.serviceNames = serviceNames
    }
}
