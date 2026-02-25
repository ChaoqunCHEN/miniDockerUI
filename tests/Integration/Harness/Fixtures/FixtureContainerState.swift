import Foundation

/// Desired state for a fixture container after creation.
enum FixtureContainerState: Sendable {
    case created // docker create (not started)
    case running // docker create + docker start
    case stopped // docker create + docker start + docker stop
}
