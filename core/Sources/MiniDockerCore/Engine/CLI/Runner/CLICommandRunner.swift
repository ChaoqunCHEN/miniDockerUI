@preconcurrency import Dispatch
import Foundation
import os

/// A stateless, ``Sendable`` wrapper around Foundation `Process` that
/// provides async one-shot execution and streaming of CLI commands.
///
/// The implementation uses `OSAllocatedUnfairLock` to safely share the
/// process reference across the cancellation handler and the termination
/// callback, satisfying Swift 6 strict concurrency requirements.
public struct CLICommandRunner: Sendable {
    public init() {}

    // MARK: - Public API

    /// Execute a one-shot command and collect the result.
    ///
    /// This method **never** throws for non-zero exit codes. Inspect
    /// ``CommandResult/isSuccess`` or ``CommandResult/exitCode`` instead.
    ///
    /// - Throws: ``CoreError/processLaunchFailed(executablePath:reason:)``
    ///           if the process cannot be started,
    ///           ``CoreError/processTimeout(executablePath:timeoutSeconds:)``
    ///           if the timeout elapses,
    ///           ``CoreError/processCancelled(executablePath:)``
    ///           if the calling Task is cancelled.
    public func run(_ request: CommandRequest) async throws -> CommandResult {
        let clock = ContinuousClock()
        let startInstant = clock.now

        // Shared mutable state protected by a lock.
        let state = OSAllocatedUnfairLock(initialState: ProcessRunState())

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // -- Build Process & Pipes --
                let process = Process()
                process.executableURL = URL(fileURLWithPath: request.executablePath)
                process.arguments = request.arguments

                if let env = request.environment {
                    var merged = ProcessInfo.processInfo.environment
                    for (key, value) in env {
                        merged[key] = value
                    }
                    process.environment = merged
                }

                if let workDir = request.workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: workDir)
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Store the process so the cancellation handler can reach it.
                state.withLock { $0.process = process }

                // -- Timeout scheduling --
                // Store the work item in the lock so it can be safely
                // accessed from the @Sendable termination handler.
                if let timeout = request.timeoutSeconds {
                    let item = DispatchWorkItem { [state] in
                        state.withLock { runState in
                            guard !runState.isFinished else { return }
                            runState.didTimeout = true
                            runState.process?.terminate()
                        }
                    }
                    state.withLock { $0.timeoutItem = item }
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + timeout,
                        execute: item
                    )
                }

                // -- Termination handler (called on process exit) --
                // This is the ONLY place that resumes the continuation.
                // The onCancel and timeout handlers just set flags and
                // terminate the process; this handler reads the flags and
                // resumes accordingly.
                process.terminationHandler = { [state] _ in
                    state.withLock { $0.timeoutItem?.cancel() }

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let shouldResume = state.withLock { runState -> Bool in
                        guard !runState.isFinished else { return false }
                        runState.isFinished = true
                        return true
                    }

                    guard shouldResume else { return }

                    let duration = clock.now - startInstant
                    let durationSeconds = Double(duration.components.seconds)
                        + Double(duration.components.attoseconds) / 1e18

                    let (didTimeout, didCancel) = state.withLock {
                        ($0.didTimeout, $0.didCancel)
                    }

                    if didCancel {
                        continuation.resume(throwing: CoreError.processCancelled(
                            executablePath: request.executablePath
                        ))
                        return
                    }

                    if didTimeout {
                        continuation.resume(throwing: CoreError.processTimeout(
                            executablePath: request.executablePath,
                            timeoutSeconds: request.timeoutSeconds ?? 0
                        ))
                        return
                    }

                    let exitCode = state.withLock { runState -> Int32 in
                        runState.process?.terminationStatus ?? -1
                    }

                    let result = CommandResult(
                        exitCode: exitCode,
                        stdout: stdoutData,
                        stderr: stderrData,
                        durationSeconds: durationSeconds
                    )
                    continuation.resume(returning: result)
                }

                // -- Launch --
                do {
                    try process.run()
                } catch {
                    state.withLock { runState in
                        runState.timeoutItem?.cancel()
                        runState.isFinished = true
                    }
                    continuation.resume(throwing: CoreError.processLaunchFailed(
                        executablePath: request.executablePath,
                        reason: error.localizedDescription
                    ))
                    return
                }

                // If the task was already cancelled before we launched,
                // set the flag and terminate. The terminationHandler
                // will resume the continuation with processCancelled.
                if Task.isCancelled {
                    state.withLock { runState in
                        guard !runState.isFinished else { return }
                        runState.didCancel = true
                        runState.timeoutItem?.cancel()
                    }
                    process.terminate()
                }
            }
        } onCancel: {
            // Only set the flag and terminate. The terminationHandler
            // is the single point that resumes the continuation.
            state.withLock { runState in
                guard !runState.isFinished else { return }
                runState.didCancel = true
                runState.timeoutItem?.cancel()
                runState.process?.terminate()
            }
        }
    }

    /// Execute a command and throw if the exit code is non-zero.
    ///
    /// This is a convenience wrapper around ``run(_:)`` that maps
    /// non-zero exits to ``CoreError/processNonZeroExit(executablePath:exitCode:stderr:)``.
    public func runChecked(_ request: CommandRequest) async throws -> CommandResult {
        let result = try await run(request)
        guard result.isSuccess else {
            throw CoreError.processNonZeroExit(
                executablePath: request.executablePath,
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result
    }

    /// Stream stdout data chunks from a running command.
    ///
    /// Each element in the returned stream is a `Data` chunk read from
    /// the process's standard output pipe as it becomes available.
    /// When the process exits with a non-zero code, the stream throws
    /// ``CoreError/processNonZeroExit(executablePath:exitCode:stderr:)``.
    public func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let processLock = OSAllocatedUnfairLock<Process?>(initialState: nil)

            let task = Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: request.executablePath)
                process.arguments = request.arguments

                if let env = request.environment {
                    var merged = ProcessInfo.processInfo.environment
                    for (key, value) in env {
                        merged[key] = value
                    }
                    process.environment = merged
                }

                if let workDir = request.workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: workDir)
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                processLock.withLock { $0 = process }

                let stdoutHandle = stdoutPipe.fileHandleForReading

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: CoreError.processLaunchFailed(
                        executablePath: request.executablePath,
                        reason: error.localizedDescription
                    ))
                    return
                }

                // Yield stdout chunks in a loop.
                while true {
                    try Task.checkCancellation()
                    let data = stdoutHandle.availableData
                    if data.isEmpty {
                        break
                    }
                    continuation.yield(data)
                }

                // Wait for the process to finish.
                process.waitUntilExit()

                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.finish(throwing: CoreError.processNonZeroExit(
                        executablePath: request.executablePath,
                        exitCode: exitCode,
                        stderr: stderrString
                    ))
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                processLock.withLock { process in
                    if let p = process, p.isRunning {
                        p.terminate()
                    }
                }
            }
        }
    }
}

// MARK: - Internal Helpers

/// Mutable state shared between the continuation, the termination handler,
/// and the cancellation handler during a `run()` call.
private struct ProcessRunState: Sendable {
    nonisolated(unsafe) var process: Process?
    nonisolated(unsafe) var timeoutItem: DispatchWorkItem?
    var isFinished: Bool = false
    var didTimeout: Bool = false
    var didCancel: Bool = false
}
