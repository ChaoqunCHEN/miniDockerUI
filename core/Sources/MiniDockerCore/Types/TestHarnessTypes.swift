import Foundation

public struct FixtureDescriptor: Codable, Equatable, Sendable {
    public var key: String
    public var image: String
    public var command: [String]
    public var environment: [String: String]

    public init(key: String, image: String, command: [String], environment: [String: String]) {
        self.key = key
        self.image = image
        self.command = command
        self.environment = environment
    }
}

public struct FixtureHandle: Codable, Equatable, Sendable {
    public var key: String
    public var containerId: String

    public init(key: String, containerId: String) {
        self.key = key
        self.containerId = containerId
    }
}

public enum ReadinessSignal: String, Codable, CaseIterable, Sendable {
    case healthy
    case unhealthy
    case regexMatched
}

public struct ReadinessObservation: Codable, Equatable, Sendable {
    public var signal: ReadinessSignal
    public var observedAt: Date
    public var details: String?

    public init(signal: ReadinessSignal, observedAt: Date, details: String?) {
        self.signal = signal
        self.observedAt = observedAt
        self.details = details
    }
}

public struct ReadinessProbeExpectation: Codable, Equatable, Sendable {
    public var expectedReady: Bool
    public var windowStart: Date
    public var windowEnd: Date

    public init(expectedReady: Bool, windowStart: Date, windowEnd: Date) {
        self.expectedReady = expectedReady
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

public struct LogLoadProfile: Codable, Equatable, Sendable {
    public var lineCount: Int
    public var bytesPerLine: Int
    public var intervalMilliseconds: Int

    public init(lineCount: Int, bytesPerLine: Int, intervalMilliseconds: Int) {
        self.lineCount = lineCount
        self.bytesPerLine = bytesPerLine
        self.intervalMilliseconds = intervalMilliseconds
    }
}

public struct LogLoadResult: Codable, Equatable, Sendable {
    public var generatedLines: Int
    public var generatedBytes: Int
    public var startedAt: Date
    public var finishedAt: Date

    public init(generatedLines: Int, generatedBytes: Int, startedAt: Date, finishedAt: Date) {
        self.generatedLines = generatedLines
        self.generatedBytes = generatedBytes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
