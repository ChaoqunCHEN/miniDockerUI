import Foundation

/// Detects Docker Compose projects from container labels.
///
/// Docker Compose automatically applies these labels to containers:
/// - `com.docker.compose.project` — project name
/// - `com.docker.compose.project.working_dir` — working directory
/// - `com.docker.compose.project.config_files` — compose file paths (comma-separated)
/// - `com.docker.compose.service` — service name
public struct ComposeProjectDetector: Sendable {
    // MARK: - Label Key Constants

    /// Label key for the compose project name.
    public static let projectLabelKey = "com.docker.compose.project"
    /// Label key for the compose project working directory.
    public static let workingDirLabelKey = "com.docker.compose.project.working_dir"
    /// Label key for the compose project config files (comma-separated).
    public static let configFilesLabelKey = "com.docker.compose.project.config_files"
    /// Label key for the compose service name.
    public static let serviceLabelKey = "com.docker.compose.service"

    public init() {}

    /// Detect Docker Compose projects from a list of container summaries.
    ///
    /// Containers without the `com.docker.compose.project` label are ignored.
    /// Results are sorted alphabetically by project name.
    ///
    /// - Parameter containers: Container summaries to scan for compose labels.
    /// - Returns: Detected compose projects, sorted by `projectName`.
    public func detectProjects(from containers: [ContainerSummary]) -> [ComposeProject] {
        // Group containers by compose project name, skipping those without the label.
        var groupedByProject: [String: [ContainerSummary]] = [:]
        for container in containers {
            guard let projectName = container.labels[Self.projectLabelKey],
                  !projectName.isEmpty
            else {
                continue
            }
            groupedByProject[projectName, default: []].append(container)
        }

        // Build a ComposeProject for each group.
        let projects: [ComposeProject] = groupedByProject.map { projectName, projectContainers in
            let workingDirectory = projectContainers
                .lazy
                .compactMap { $0.labels[Self.workingDirLabelKey] }
                .first { !$0.isEmpty }
                ?? ""

            let configFilesRaw = projectContainers
                .lazy
                .compactMap { $0.labels[Self.configFilesLabelKey] }
                .first { !$0.isEmpty }
                ?? ""
            let configFiles = configFilesRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let containerIds = projectContainers.map(\.id)

            var seenServices: Set<String> = []
            var serviceNames: [String] = []
            for container in projectContainers {
                if let service = container.labels[Self.serviceLabelKey],
                   !service.isEmpty,
                   !seenServices.contains(service)
                {
                    seenServices.insert(service)
                    serviceNames.append(service)
                }
            }

            return ComposeProject(
                projectName: projectName,
                workingDirectory: workingDirectory,
                configFiles: configFiles,
                containerIds: containerIds,
                serviceNames: serviceNames
            )
        }

        return projects.sorted { $0.projectName < $1.projectName }
    }
}
