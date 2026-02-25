import Foundation

/// Typed container event actions the reducer understands.
public enum ContainerEvent: String, Sendable, CaseIterable {
    case create
    case start
    case stop
    case die
    case destroy
    case pause
    case unpause
    case rename
    case healthStatus = "health_status"

    /// Classify a raw Docker event action string.
    /// Returns `nil` for unrecognized actions (exec, network, etc.).
    public static func classify(_ action: String) -> ContainerEvent? {
        let trimmed = action.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? action
        return ContainerEvent(rawValue: trimmed)
    }
}
