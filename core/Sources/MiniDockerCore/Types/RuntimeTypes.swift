import Foundation

public enum EngineEndpointType: String, Sendable, Codable, CaseIterable {
    case local
    case tcp
    case ssh
    case tls
}

public struct EngineEndpoint: Sendable, Codable, Equatable {
    public let endpointType: EngineEndpointType
    public let address: String

    public init(endpointType: EngineEndpointType, address: String) {
        self.endpointType = endpointType
        self.address = address
    }
}

public struct EngineContext: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let endpointType: EngineEndpointType
    public let isReachable: Bool
    public let lastCheckedAt: Date?

    public init(
        id: String,
        name: String,
        endpointType: EngineEndpointType,
        isReachable: Bool,
        lastCheckedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.endpointType = endpointType
        self.isReachable = isReachable
        self.lastCheckedAt = lastCheckedAt
    }
}

public enum ContainerHealthStatus: String, Sendable, Codable, CaseIterable {
    case healthy
    case unhealthy
    case starting
    case none
    case unknown
}

public struct ContainerSummary: Sendable, Codable, Equatable {
    public let engineContextId: String
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let health: ContainerHealthStatus?
    public let labels: [String: String]
    public let startedAt: Date?

    public init(
        engineContextId: String,
        id: String,
        name: String,
        image: String,
        status: String,
        health: ContainerHealthStatus?,
        labels: [String: String],
        startedAt: Date?
    ) {
        self.engineContextId = engineContextId
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.health = health
        self.labels = labels
        self.startedAt = startedAt
    }
}

// MARK: - ContainerSummary Computed Properties

public enum ContainerStatusColor: String, Sendable, CaseIterable {
    case running
    case warning
    case stopped
}

public extension ContainerSummary {
    var isRunning: Bool {
        let lower = status.lowercased()
        return lower.hasPrefix("up") || lower == "running"
    }

    var displayStatus: String {
        if isRunning { return "Running" }
        let lower = status.lowercased()
        if lower.contains("exited") { return "Exited" }
        if lower.contains("created") { return "Created" }
        if lower.contains("paused") { return "Paused" }
        return status
    }

    var statusColor: ContainerStatusColor {
        if isRunning {
            if health == .unhealthy || health == .starting { return .warning }
            return .running
        }
        return .stopped
    }
}

public struct ContainerMount: Sendable, Codable, Equatable {
    public let source: String
    public let destination: String
    public let mode: String
    public let isReadOnly: Bool

    public init(source: String, destination: String, mode: String, isReadOnly: Bool) {
        self.source = source
        self.destination = destination
        self.mode = mode
        self.isReadOnly = isReadOnly
    }
}

public struct ContainerPortBinding: Sendable, Codable, Equatable {
    public let containerPort: String
    public let hostIP: String?
    public let hostPort: UInt16?

    public init(containerPort: String, hostIP: String?, hostPort: UInt16?) {
        self.containerPort = containerPort
        self.hostIP = hostIP
        self.hostPort = hostPort
    }
}

public struct ContainerNetworkSettings: Sendable, Codable, Equatable {
    public let networkMode: String
    public let ipAddressesByNetwork: [String: String]
    public let ports: [ContainerPortBinding]

    public init(networkMode: String, ipAddressesByNetwork: [String: String], ports: [ContainerPortBinding]) {
        self.networkMode = networkMode
        self.ipAddressesByNetwork = ipAddressesByNetwork
        self.ports = ports
    }
}

public struct ContainerHealthLog: Sendable, Codable, Equatable {
    public let startedAt: Date
    public let endedAt: Date
    public let exitCode: Int32
    public let output: String

    public init(startedAt: Date, endedAt: Date, exitCode: Int32, output: String) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.output = output
    }
}

public struct ContainerHealthDetail: Sendable, Codable, Equatable {
    public let status: ContainerHealthStatus
    public let failingStreak: Int
    public let logs: [ContainerHealthLog]

    public init(status: ContainerHealthStatus, failingStreak: Int, logs: [ContainerHealthLog]) {
        self.status = status
        self.failingStreak = failingStreak
        self.logs = logs
    }
}

public struct ContainerDetail: Sendable, Codable, Equatable {
    public let summary: ContainerSummary
    public let mounts: [ContainerMount]
    public let networkSettings: ContainerNetworkSettings
    public let healthDetail: ContainerHealthDetail?
    public let rawInspect: JSONValue

    public init(
        summary: ContainerSummary,
        mounts: [ContainerMount],
        networkSettings: ContainerNetworkSettings,
        healthDetail: ContainerHealthDetail?,
        rawInspect: JSONValue
    ) {
        self.summary = summary
        self.mounts = mounts
        self.networkSettings = networkSettings
        self.healthDetail = healthDetail
        self.rawInspect = rawInspect
    }
}

public enum ContainerAction: String, Sendable, Codable, CaseIterable {
    case start
    case stop
    case restart
    case viewLogs
    case inspect
}

public struct EventEnvelope: Sendable, Codable, Equatable {
    public let sequence: UInt64
    public let eventAt: Date
    public let containerId: String?
    public let action: String
    public let attributes: [String: String]
    public let source: String
    public let raw: JSONValue?

    public init(
        sequence: UInt64,
        eventAt: Date,
        containerId: String?,
        action: String,
        attributes: [String: String],
        source: String,
        raw: JSONValue?
    ) {
        self.sequence = sequence
        self.eventAt = eventAt
        self.containerId = containerId
        self.action = action
        self.attributes = attributes
        self.source = source
        self.raw = raw
    }
}

public enum LogStream: String, Sendable, Codable, CaseIterable {
    case stdout
    case stderr
    case system
}

public struct LogEntry: Sendable, Codable, Equatable {
    public let engineContextId: String
    public let containerId: String
    public let stream: LogStream
    public let timestamp: Date
    public let message: String

    public init(
        engineContextId: String,
        containerId: String,
        stream: LogStream,
        timestamp: Date,
        message: String
    ) {
        self.engineContextId = engineContextId
        self.containerId = containerId
        self.stream = stream
        self.timestamp = timestamp
        self.message = message
    }
}

public struct LogStreamOptions: Sendable, Codable, Equatable {
    public let since: Date?
    public let tail: Int?
    public let includeStdout: Bool
    public let includeStderr: Bool
    public let timestamps: Bool
    public let follow: Bool

    public init(
        since: Date?,
        tail: Int?,
        includeStdout: Bool,
        includeStderr: Bool,
        timestamps: Bool,
        follow: Bool
    ) {
        self.since = since
        self.tail = tail
        self.includeStdout = includeStdout
        self.includeStderr = includeStderr
        self.timestamps = timestamps
        self.follow = follow
    }
}

public enum LogDropStrategy: String, Sendable, Codable {
    case dropOldest
    case dropNewest
    case blockProducer
}

public struct LogBufferPolicy: Sendable, Codable, Equatable {
    public let maxLinesPerContainer: Int
    public let maxBytesPerContainer: Int
    public let dropStrategy: LogDropStrategy
    public let flushHz: Int

    public init(
        maxLinesPerContainer: Int,
        maxBytesPerContainer: Int,
        dropStrategy: LogDropStrategy,
        flushHz: Int
    ) {
        self.maxLinesPerContainer = maxLinesPerContainer
        self.maxBytesPerContainer = maxBytesPerContainer
        self.dropStrategy = dropStrategy
        self.flushHz = flushHz
    }
}

public enum ReadinessMode: String, Sendable, Codable, CaseIterable {
    case healthOnly
    case healthThenRegex
    case regexOnly
}

public enum ReadinessWindowStartPolicy: String, Sendable, Codable, CaseIterable {
    case containerStart
    case actionDispatch
    case firstLogEntry
}

public struct ReadinessRule: Sendable, Codable, Equatable {
    public let mode: ReadinessMode
    public let regexPattern: String?
    public let mustMatchCount: Int
    public let windowStartPolicy: ReadinessWindowStartPolicy

    public init(
        mode: ReadinessMode,
        regexPattern: String?,
        mustMatchCount: Int,
        windowStartPolicy: ReadinessWindowStartPolicy
    ) {
        self.mode = mode
        self.regexPattern = regexPattern
        self.mustMatchCount = mustMatchCount
        self.windowStartPolicy = windowStartPolicy
    }
}

public enum WorktreeTargetType: String, Sendable, Codable, CaseIterable {
    case container
    case composeProject
}

public enum WorktreeRestartPolicy: String, Sendable, Codable, CaseIterable {
    case never
    case ifRunning
    case always
}

public struct WorktreeMapping: Sendable, Codable, Equatable {
    public let id: String
    public let repoRoot: String
    public let anchorPath: String
    public let targetType: WorktreeTargetType
    public let targetId: String
    public let restartPolicy: WorktreeRestartPolicy

    public init(
        id: String,
        repoRoot: String,
        anchorPath: String,
        targetType: WorktreeTargetType,
        targetId: String,
        restartPolicy: WorktreeRestartPolicy
    ) {
        self.id = id
        self.repoRoot = repoRoot
        self.anchorPath = anchorPath
        self.targetType = targetType
        self.targetId = targetId
        self.restartPolicy = restartPolicy
    }
}

public struct WorktreeSwitchPlan: Sendable, Codable, Equatable {
    public let mappingId: String
    public let fromWorktree: String
    public let toWorktree: String
    public let restartTargets: [String]
    public let verifyRule: ReadinessRule

    public init(
        mappingId: String,
        fromWorktree: String,
        toWorktree: String,
        restartTargets: [String],
        verifyRule: ReadinessRule
    ) {
        self.mappingId = mappingId
        self.fromWorktree = fromWorktree
        self.toWorktree = toWorktree
        self.restartTargets = restartTargets
        self.verifyRule = verifyRule
    }
}

public struct AppSettings: Sendable, Codable, Equatable {
    public let schemaVersion: String
    public let favoriteContainerKeys: Set<String>
    public let actionPreferences: [String: String]
    public let worktreeMappings: [WorktreeMapping]
    public let readinessRules: [String: ReadinessRule]
    public let transientUIPreferences: [String: JSONValue]

    public init(
        schemaVersion: String,
        favoriteContainerKeys: Set<String>,
        actionPreferences: [String: String],
        worktreeMappings: [WorktreeMapping],
        readinessRules: [String: ReadinessRule],
        transientUIPreferences: [String: JSONValue]
    ) {
        self.schemaVersion = schemaVersion
        self.favoriteContainerKeys = favoriteContainerKeys
        self.actionPreferences = actionPreferences
        self.worktreeMappings = worktreeMappings
        self.readinessRules = readinessRules
        self.transientUIPreferences = transientUIPreferences
    }
}

public extension AppSettings {
    func with(favoriteContainerKeys: Set<String>) -> AppSettings {
        AppSettings(
            schemaVersion: schemaVersion,
            favoriteContainerKeys: favoriteContainerKeys,
            actionPreferences: actionPreferences,
            worktreeMappings: worktreeMappings,
            readinessRules: readinessRules,
            transientUIPreferences: transientUIPreferences
        )
    }
}

public typealias AppSettingsSnapshot = AppSettings
