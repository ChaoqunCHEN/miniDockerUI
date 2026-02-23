import Foundation

/// Parses JSON output from `docker inspect <id>`.
///
/// Docker inspect returns a JSON array (typically one element).
/// The parser maps the nested structure to ``ContainerDetail``.
public struct ContainerInspectParser: Sendable {
    public init() {}

    /// Parse `docker inspect` output into a ``ContainerDetail``.
    public func parseInspect(output: String, engineContextId: String) throws -> ContainerDetail {
        guard let data = output.data(using: .utf8),
              let topLevel = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let json = topLevel.first
        else {
            throw CoreError.outputParseFailure(
                context: "docker inspect root array",
                rawSnippet: String(output.prefix(200))
            )
        }

        let summary = try extractSummary(from: json, engineContextId: engineContextId)
        let mounts = extractMounts(from: json)
        let networkSettings = extractNetworkSettings(from: json)
        let healthDetail = extractHealthDetail(from: json)
        let rawInspect = convertToJSONValue(data: data)

        return ContainerDetail(
            summary: summary,
            mounts: mounts,
            networkSettings: networkSettings,
            healthDetail: healthDetail,
            rawInspect: rawInspect
        )
    }

    // MARK: - Summary Extraction

    private func extractSummary(
        from json: [String: Any],
        engineContextId: String
    ) throws -> ContainerSummary {
        guard let id = json["Id"] as? String else {
            throw CoreError.outputParseFailure(
                context: "docker inspect missing Id",
                rawSnippet: ""
            )
        }

        let rawName = (json["Name"] as? String) ?? ""
        let name = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName

        let config = json["Config"] as? [String: Any]
        let image = (config?["Image"] as? String) ?? ""

        let state = json["State"] as? [String: Any]
        let status = (state?["Status"] as? String) ?? ""

        let health: ContainerHealthStatus?
        if let healthObj = state?["Health"] as? [String: Any],
           let healthStr = healthObj["Status"] as? String
        {
            health = ContainerHealthStatus(rawValue: healthStr)
        } else {
            health = nil
        }

        let labels = (config?["Labels"] as? [String: String]) ?? [:]

        let startedAt: Date?
        if let startedAtStr = state?["StartedAt"] as? String {
            startedAt = DockerDateParser.parseRFC3339Nano(startedAtStr)
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

    // MARK: - Mounts

    private func extractMounts(from json: [String: Any]) -> [ContainerMount] {
        guard let mountsArray = json["Mounts"] as? [[String: Any]] else { return [] }
        return mountsArray.compactMap { mount in
            let source = (mount["Source"] as? String) ?? ""
            let destination = (mount["Destination"] as? String) ?? ""
            let mode = (mount["Mode"] as? String) ?? ""
            let rw = (mount["RW"] as? Bool) ?? true
            return ContainerMount(source: source, destination: destination, mode: mode, isReadOnly: !rw)
        }
    }

    // MARK: - Network Settings

    private func extractNetworkSettings(from json: [String: Any]) -> ContainerNetworkSettings {
        let ns = json["NetworkSettings"] as? [String: Any]

        // Network mode from HostConfig
        let hostConfig = json["HostConfig"] as? [String: Any]
        let networkMode = (hostConfig?["NetworkMode"] as? String) ?? ""

        // IP addresses by network
        var ipByNetwork: [String: String] = [:]
        if let networks = ns?["Networks"] as? [String: [String: Any]] {
            for (netName, netInfo) in networks {
                if let ip = netInfo["IPAddress"] as? String, !ip.isEmpty {
                    ipByNetwork[netName] = ip
                }
            }
        }

        // Port bindings
        var ports: [ContainerPortBinding] = []
        if let portsMap = ns?["Ports"] as? [String: Any] {
            for (containerPort, bindings) in portsMap {
                if let bindingArray = bindings as? [[String: String]] {
                    for binding in bindingArray {
                        let hostIP = binding["HostIp"]
                        let hostPortStr = binding["HostPort"]
                        let hostPort = hostPortStr.flatMap { UInt16($0) }
                        ports.append(ContainerPortBinding(
                            containerPort: containerPort,
                            hostIP: hostIP,
                            hostPort: hostPort
                        ))
                    }
                } else {
                    ports.append(ContainerPortBinding(
                        containerPort: containerPort,
                        hostIP: nil,
                        hostPort: nil
                    ))
                }
            }
        }

        return ContainerNetworkSettings(
            networkMode: networkMode,
            ipAddressesByNetwork: ipByNetwork,
            ports: ports
        )
    }

    // MARK: - Health Detail

    private func extractHealthDetail(from json: [String: Any]) -> ContainerHealthDetail? {
        let state = json["State"] as? [String: Any]
        guard let healthObj = state?["Health"] as? [String: Any] else { return nil }

        let statusStr = (healthObj["Status"] as? String) ?? "unknown"
        let status = ContainerHealthStatus(rawValue: statusStr) ?? .unknown
        let failingStreak = (healthObj["FailingStreak"] as? Int) ?? 0

        var logs: [ContainerHealthLog] = []
        if let logArray = healthObj["Log"] as? [[String: Any]] {
            for logItem in logArray {
                let startStr = (logItem["Start"] as? String) ?? ""
                let endStr = (logItem["End"] as? String) ?? ""
                let exitCode = Int32((logItem["ExitCode"] as? Int) ?? 0)
                let output = (logItem["Output"] as? String) ?? ""

                guard let startDate = DockerDateParser.parseRFC3339Nano(startStr),
                      let endDate = DockerDateParser.parseRFC3339Nano(endStr)
                else { continue }

                logs.append(ContainerHealthLog(
                    startedAt: startDate,
                    endedAt: endDate,
                    exitCode: exitCode,
                    output: output
                ))
            }
        }

        return ContainerHealthDetail(status: status, failingStreak: failingStreak, logs: logs)
    }

    // MARK: - JSONValue Conversion

    private func convertToJSONValue(data: Data) -> JSONValue {
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .null
        }
        return decoded
    }
}
