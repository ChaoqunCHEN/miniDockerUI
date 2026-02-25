import Foundation

/// A group of containers with a section title.
public struct ContainerGroup: Sendable, Equatable {
    public let title: String
    public let containers: [ContainerSummary]

    public init(title: String, containers: [ContainerSummary]) {
        self.title = title
        self.containers = containers
    }
}

/// Pure functions for grouping and sorting containers with favorites support.
public enum ContainerGrouper {
    /// Groups containers into sections: Favorites, Running, Stopped.
    /// Favorite containers appear in a dedicated section regardless of running state.
    public static func group(
        containers: [ContainerSummary],
        favoriteKeys: Set<String>,
        keyForContainer: (ContainerSummary) -> String
    ) -> [ContainerGroup] {
        let favorites = containers.filter { favoriteKeys.contains(keyForContainer($0)) }
        let nonFavorites = containers.filter { !favoriteKeys.contains(keyForContainer($0)) }

        var groups: [ContainerGroup] = []

        if !favorites.isEmpty {
            groups.append(ContainerGroup(
                title: "Favorites",
                containers: favorites.sorted { $0.name < $1.name }
            ))
        }

        let running = nonFavorites.filter(\.isRunning).sorted { $0.name < $1.name }
        if !running.isEmpty {
            groups.append(ContainerGroup(title: "Running", containers: running))
        }

        let stopped = nonFavorites.filter { !$0.isRunning }.sorted { $0.name < $1.name }
        if !stopped.isEmpty {
            groups.append(ContainerGroup(title: "Stopped", containers: stopped))
        }

        return groups
    }

    /// Generate a stable container key for favorites identification.
    public static func containerKey(for container: ContainerSummary) -> String {
        "\(container.engineContextId):\(container.name)"
    }
}
