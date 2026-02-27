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
                let process = Self.makeProcess(for: request)

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
                            guard !runState.isFinished, runState.isLaunched else { return }
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

                // -- Read pipes on background threads --
                // Start reading BEFORE process.run() so the FDs are read
                // while still valid. The reads complete naturally when the
                // process exits (write end closes).
                let pipeGroup = DispatchGroup()
                let pipeData = OSAllocatedUnfairLock(
                    initialState: (stdout: Data(), stderr: Data())
                )

                pipeGroup.enter()
                DispatchQueue.global().async {
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    pipeData.withLock { $0.stdout = data }
                    pipeGroup.leave()
                }
                pipeGroup.enter()
                DispatchQueue.global().async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    pipeData.withLock { $0.stderr = data }
                    pipeGroup.leave()
                }

                // -- Termination handler (called on process exit) --
                // This is the ONLY place that resumes the continuation.
                // The onCancel and timeout handlers just set flags and
                // terminate the process; this handler reads the flags and
                // resumes accordingly.
                process.terminationHandler = { [state] _ in
                    state.withLock { $0.timeoutItem?.cancel() }

                    // Wait for background pipe reads to finish.
                    pipeGroup.wait()
                    let (stdoutData, stderrData) = pipeData.withLock {
                        ($0.stdout, $0.stderr)
                    }

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
                    // Close write ends so background readers unblock.
                    stdoutPipe.fileHandleForWriting.closeFile()
                    stderrPipe.fileHandleForWriting.closeFile()
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

                // Mark as launched and check if cancel/timeout arrived
                // while we were launching. This closes the race window
                // between process.run() and the isLaunched flag.
                let shouldTerminate = state.withLock { runState -> Bool in
                    runState.isLaunched = true
                    if runState.isFinished { return false }
                    if runState.didCancel || Task.isCancelled {
                        runState.didCancel = true
                        runState.timeoutItem?.cancel()
                        return true
                    }
                    return false
                }
                if shouldTerminate {
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
                if runState.isLaunched {
                    runState.process?.terminate()
                }
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
            let processLock = OSAllocatedUnfairLock(initialState: StreamProcessState())

            let task = Task {
                let process = Self.makeProcess(for: request)

                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe

                // When mergeStderr is true, redirect stderr into the same
                // pipe so both streams are yielded together to the caller.
                let stderrPipe: Pipe?
                if request.mergeStderr {
                    process.standardError = stdoutPipe
                    stderrPipe = nil
                } else {
                    let separate = Pipe()
                    process.standardError = separate
                    stderrPipe = separate
                }

                let stdoutHandle = stdoutPipe.fileHandleForReading
                processLock.withLock { $0.process = process }

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: CoreError.processLaunchFailed(
                        executablePath: request.executablePath,
                        reason: error.localizedDescription
                    ))
                    return
                }

                processLock.withLock { $0.isLaunched = true }

                // Read stderr on a background thread so the FD is read
                // while still valid (same pattern as run() fix).
                // Skipped when stderr is merged into stdout.
                let stderrGroup = DispatchGroup()
                let stderrResult = OSAllocatedUnfairLock(initialState: Data())
                if let stderrPipe {
                    stderrGroup.enter()
                    DispatchQueue.global().async {
                        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        stderrResult.withLock { $0 = data }
                        stderrGroup.leave()
                    }
                }

                // Yield stdout chunks in a loop.
                do {
                    while true {
                        try Task.checkCancellation()
                        let data = stdoutHandle.availableData
                        if data.isEmpty {
                            break
                        }
                        continuation.yield(data)
                    }
                } catch {
                    // Cancelled — clean up the process and finish the stream.
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.finish(throwing: error)
                    return
                }

                // Wait for the process to finish.
                process.waitUntilExit()

                // Wait for stderr read to complete (bridged for async context).
                // Skipped when stderr is merged (no separate reader).
                if stderrPipe != nil {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        stderrGroup.notify(queue: .global()) {
                            cont.resume()
                        }
                    }
                }

                let exitCode = process.terminationStatus
                guard exitCode != 0 else {
                    continuation.finish()
                    return
                }
                let stderrData = stderrResult.withLock { $0 }
                let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.finish(throwing: CoreError.processNonZeroExit(
                    executablePath: request.executablePath,
                    exitCode: exitCode,
                    stderr: stderrString
                ))
            }

            continuation.onTermination = { _ in
                task.cancel()
                processLock.withLock { state in
                    if let p = state.process, state.isLaunched, p.isRunning {
                        // Terminating closes the write end of the pipes,
                        // which unblocks availableData naturally.
                        p.terminate()
                    }
                }
            }
        }
    }

    // MARK: - Private Helpers

    private static func makeProcess(for request: CommandRequest) -> Process {
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

        return process
    }
}

// MARK: - Internal Helpers

/// Mutable state shared between the continuation, the termination handler,
/// and the cancellation handler during a `run()` call.
private struct ProcessRunState: Sendable {
    nonisolated(unsafe) var process: Process?
    nonisolated(unsafe) var timeoutItem: DispatchWorkItem?
    var isLaunched: Bool = false
    var isFinished: Bool = false
    var didTimeout: Bool = false
    var didCancel: Bool = false
}

/// Mutable state shared between the stream task and the onTermination
/// handler during a `stream()` call.
private struct StreamProcessState: Sendable {
    nonisolated(unsafe) var process: Process?
    var isLaunched: Bool = false
}
