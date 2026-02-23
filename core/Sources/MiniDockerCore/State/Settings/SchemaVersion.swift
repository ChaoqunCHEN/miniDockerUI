import Foundation

/// Semver-style schema version for settings file migration.
///
/// Versions are compared lexicographically by major, minor, patch.
/// String representation is "major.minor.patch".
public struct SchemaVersion: Sendable, Codable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse from a string like "1.2.3".
    ///
    /// - Throws: `CoreError.outputParseFailure` when the string does not
    ///   contain exactly three dot-separated non-negative integers.
    public init(parsing string: String) throws {
        let components = string.split(separator: ".")
        guard components.count == 3,
              let majorValue = Int(components[0]), majorValue >= 0,
              let minorValue = Int(components[1]), minorValue >= 0,
              let patchValue = Int(components[2]), patchValue >= 0
        else {
            throw CoreError.outputParseFailure(
                context: "SchemaVersion",
                rawSnippet: string
            )
        }
        major = majorValue
        minor = minorValue
        patch = patchValue
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
