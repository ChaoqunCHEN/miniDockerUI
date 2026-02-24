import Foundation

/// Implements ``EngineAdapter`` by delegating to the Docker CLI.
///
/// Composes ``CLICommandRunner`` (Wave 1) with the output parsers
/// (Wave 2) to provide a full container lifecycle API.
public struct CLIEngineAdapter: EngineAdapter, Sendable {
    private let runner: any CommandRunning
    private let dockerPath: String
    private let engineContextId: String
    private let listParser: ContainerListParser
    private let inspectParser: ContainerInspectParser
    private let eventParser: EventStreamParser
    private let logParser: LogStreamParser

    /// Default timeout for one-shot commands (seconds).
    private let defaultTimeout: Double = 30

    public init(
        dockerPath: String = "/usr/local/bin/docker",
        engineContextId: String = "local",
        runner: any CommandRunning = CLICommandRunner()
    ) {
        self.dockerPath = dockerPath
        self.engineContextId = engineContextId
        self.runner = runner
        listParser = ContainerListParser()
        inspectParser = ContainerInspectParser()
        eventParser = EventStreamParser()
        logParser = LogStreamParser()
    }

    // MARK: - One-Shot Commands

    public func listContainers() async throws -> [ContainerSummary] {
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: ["ps", "-a", "--format", "json", "--no-trunc"],
            timeoutSeconds: defaultTimeout
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw CoreError.processNonZeroExit(
                executablePath: dockerPath,
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return try listParser.parseList(
            output: result.stdoutString,
            engineContextId: engineContextId
        )
    }

    public func inspectContainer(id: String) async throws -> ContainerDetail {
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: ["inspect", id],
            timeoutSeconds: defaultTimeout
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw CoreError.processNonZeroExit(
                executablePath: dockerPath,
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return try inspectParser.parseInspect(
            output: result.stdoutString,
            engineContextId: engineContextId
        )
    }

    public func startContainer(id: String) async throws {
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: ["start", id],
            timeoutSeconds: defaultTimeout
        )
        _ = try await runner.runChecked(request)
    }

    public func stopContainer(id: String, timeoutSeconds: Int?) async throws {
        var args = ["stop"]
        if let timeout = timeoutSeconds {
            args.append(contentsOf: ["--time", String(timeout)])
        }
        args.append(id)
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: args,
            timeoutSeconds: Double(timeoutSeconds ?? 30) + 5
        )
        _ = try await runner.runChecked(request)
    }

    public func restartContainer(id: String, timeoutSeconds: Int?) async throws {
        var args = ["restart"]
        if let timeout = timeoutSeconds {
            args.append(contentsOf: ["--time", String(timeout)])
        }
        args.append(id)
        let request = CommandRequest(
            executablePath: dockerPath,
            arguments: args,
            timeoutSeconds: Double(timeoutSeconds ?? 30) + 5
        )
        _ = try await runner.runChecked(request)
    }

    // MARK: - Streaming Commands

    public func streamEvents(since: Date?) -> AsyncThrowingStream<EventEnvelope, Error> {
        var args = ["events", "--format", "json"]
        if let since {
            let unixTime = Int(since.timeIntervalSince1970)
            args.append(contentsOf: ["--since", String(unixTime)])
        }
        let request = CommandRequest(executablePath: dockerPath, arguments: args)
        let dataStream = runner.stream(request)
        let parser = eventParser

        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulator = DataLineAccumulator()
                var sequence: UInt64 = 0
                do {
                    for try await chunk in dataStream {
                        let lines = accumulator.feed(chunk)
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { continue }
                            do {
                                let envelope = try parser.parseEventLine(
                                    line: trimmed,
                                    sequenceNumber: sequence
                                )
                                sequence += 1
                                continuation.yield(envelope)
                            } catch {
                                // Skip unparseable lines
                            }
                        }
                    }
                    // Flush any remaining partial line
                    if let remaining = accumulator.flush() {
                        let trimmed = remaining.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            if let envelope = try? parser.parseEventLine(
                                line: trimmed,
                                sequenceNumber: sequence
                            ) {
                                continuation.yield(envelope)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func streamLogs(id: String, options: LogStreamOptions) -> AsyncThrowingStream<LogEntry, Error> {
        var args = ["logs"]
        // Always request timestamps (parser depends on them)
        args.append("-t")
        if options.follow {
            args.append("-f")
        }
        if let tail = options.tail {
            args.append(contentsOf: ["--tail", String(tail)])
        }
        if let since = options.since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            args.append(contentsOf: ["--since", formatter.string(from: since)])
        }
        args.append(id)

        let request = CommandRequest(executablePath: dockerPath, arguments: args)
        let dataStream = runner.stream(request)
        let parser = logParser
        let ctxId = engineContextId
        let cId = id

        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulator = DataLineAccumulator()
                do {
                    for try await chunk in dataStream {
                        let lines = accumulator.feed(chunk)
                        for line in lines {
                            guard !line.isEmpty else { continue }
                            do {
                                let entry = try parser.parseLogLine(
                                    line: line,
                                    engineContextId: ctxId,
                                    containerId: cId,
                                    defaultStream: .stdout
                                )
                                continuation.yield(entry)
                            } catch {
                                // Skip unparseable lines
                            }
                        }
                    }
                    if let remaining = accumulator.flush() {
                        if !remaining.isEmpty {
                            if let entry = try? parser.parseLogLine(
                                line: remaining,
                                engineContextId: ctxId,
                                containerId: cId,
                                defaultStream: .stdout
                            ) {
                                continuation.yield(entry)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
