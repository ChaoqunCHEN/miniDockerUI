import Foundation

/// Parses JSON lines from `docker events --format json`.
///
/// Each line is a standalone JSON object representing a single Docker event.
/// Designed for line-by-line streaming consumption.
public struct EventStreamParser: Sendable {
    public init() {}

    /// Parse a single JSON line into an ``EventEnvelope``.
    ///
    /// - Parameters:
    ///   - line: A single JSON line from `docker events --format json`.
    ///   - sequenceNumber: Monotonically increasing sequence assigned by the caller.
    public func parseEventLine(line: String, sequenceNumber: UInt64) throws -> EventEnvelope {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CoreError.outputParseFailure(
                context: "docker events JSON line",
                rawSnippet: String(line.prefix(200))
            )
        }

        // Action: prefer "Action", fallback to "status"
        let action = (json["Action"] as? String) ?? (json["status"] as? String) ?? ""

        // Container ID: prefer Actor.ID, fallback to "id"
        let containerId: String?
        if let actor = json["Actor"] as? [String: Any] {
            let actorId = actor["ID"] as? String
            containerId = (actorId?.isEmpty == false) ? actorId : (json["id"] as? String)
        } else {
            containerId = json["id"] as? String
        }

        // Attributes from Actor.Attributes
        let attributes: [String: String]
        if let actor = json["Actor"] as? [String: Any],
           let attrs = actor["Attributes"] as? [String: String]
        {
            attributes = attrs
        } else {
            attributes = [:]
        }

        // Source: "Type" field
        let source = (json["Type"] as? String) ?? ""

        // Timestamp: prefer timeNano, fallback to time
        let eventAt: Date
        if let timeNano = json["timeNano"] as? Int64 {
            eventAt = DockerDateParser.parseUnixNano(nanoseconds: timeNano)
        } else if let timeNano = json["timeNano"] as? Double {
            eventAt = DockerDateParser.parseUnixNano(nanoseconds: Int64(timeNano))
        } else if let timeSec = json["time"] as? Double {
            eventAt = Date(timeIntervalSince1970: timeSec)
        } else if let timeSec = json["time"] as? Int {
            eventAt = Date(timeIntervalSince1970: TimeInterval(timeSec))
        } else {
            eventAt = Date()
        }

        // Raw JSON as JSONValue
        let raw: JSONValue?
        if let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            raw = decoded
        } else {
            raw = nil
        }

        return EventEnvelope(
            sequence: sequenceNumber,
            eventAt: eventAt,
            containerId: containerId,
            action: action,
            attributes: attributes,
            source: source,
            raw: raw
        )
    }
}
