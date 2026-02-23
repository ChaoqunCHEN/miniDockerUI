import Foundation

/// Parses NDJSON output from `docker ps --format json`.
///
/// Each line is a standalone JSON object. The parser maps Docker's
/// field names to ``ContainerSummary`` domain types.
public struct ContainerListParser: Sendable {
    public init() {}

    /// Parse multi-line NDJSON output into an array of container summaries.
    ///
    /// Empty or whitespace-only lines are silently skipped.
    /// An empty input string returns an empty array (not an error).
    public func parseList(output: String, engineContextId: String) throws -> [ContainerSummary] {
        let lines = output.components(separatedBy: .newlines)
        var results: [ContainerSummary] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let summary = try parseSingleContainer(jsonLine: trimmed, engineContextId: engineContextId)
            results.append(summary)
        }
        return results
    }

    /// Parse a single JSON line into a ``ContainerSummary``.
    public func parseSingleContainer(jsonLine: String, engineContextId: String) throws -> ContainerSummary {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CoreError.outputParseFailure(
                context: "docker ps JSON line",
                rawSnippet: String(jsonLine.prefix(200))
            )
        }

        guard let id = json["ID"] as? String, !id.isEmpty else {
            throw CoreError.outputParseFailure(
                context: "docker ps missing ID field",
                rawSnippet: String(jsonLine.prefix(200))
            )
        }

        let rawName = (json["Names"] as? String) ?? ""
        let name = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName

        let image = (json["Image"] as? String) ?? ""
        let status = (json["Status"] as? String) ?? ""
        let health = extractHealth(from: status)
        let labels = parseLabels(json["Labels"] as? String)

        let startedAt: Date?
        if let createdAt = json["CreatedAt"] as? String {
            startedAt = DockerDateParser.parseCLIDate(createdAt)
        } else {
            startedAt = nil
        }

        return ContainerSummary(
            engineContextId: engineContextId,
            id: id,
            name: name,
            image: image,
            status: status,
            health: health,
            labels: labels,
            startedAt: startedAt
        )
    }

    // MARK: - Private

    /// Extract health status from Docker's Status string.
    ///
    /// Docker embeds health in parentheses: "Up 2 hours (healthy)",
    /// "Up 5 minutes (health: starting)", "Up 1 hour (unhealthy)".
    private func extractHealth(from status: String) -> ContainerHealthStatus? {
        guard let openParen = status.lastIndex(of: "("),
              let closeParen = status.lastIndex(of: ")")
        else {
            return nil
        }

        let inner = status[status.index(after: openParen) ..< closeParen]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        if inner == "healthy" { return .healthy }
        if inner == "unhealthy" { return .unhealthy }
        if inner.contains("starting") { return .starting }
        return nil
    }

    /// Parse Docker's comma-separated `key=value` label format.
    private func parseLabels(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in raw.components(separatedBy: ",") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex ..< eqIndex])
            let value = String(trimmed[trimmed.index(after: eqIndex)...])
            result[key] = value
        }
        return result
    }
}
