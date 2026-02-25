import Foundation

/// Manages the lifecycle of a Docker event stream with automatic
/// reconnection, exponential backoff, and full state resync after reconnect.
///
/// Sits ABOVE the ``EngineAdapter`` (replaceable adapters principle).
/// Produces a stream of ``SupervisorEvent`` values that include both
/// Docker events and supervisor lifecycle notifications.
///
/// The supervisor does NOT mutate ``ContainerStateHolder`` directly.
/// The consumer drives state changes based on emitted events.
public struct EventStreamSupervisor: Sendable {
    private let adapter: any EngineAdapter
    private let backoffPolicy: BackoffPolicy

    public init(
        adapter: any EngineAdapter,
        backoffPolicy: BackoffPolicy = BackoffPolicy()
    ) {
        self.adapter = adapter
        self.backoffPolicy = backoffPolicy
    }

    /// Start supervised event streaming.
    ///
    /// The returned stream:
    /// 1. Connects to the event stream via the adapter.
    /// 2. Yields `.phaseChanged(.streaming)` on successful connection.
    /// 3. Yields `.dockerEvent(envelope)` for each event.
    /// 4. On stream failure: disconnected → backoff → resync → reconnect.
    /// 5. After `maxRetries` consecutive failures: yields `.exhausted`.
    /// 6. On task cancellation: yields `.stopped`.
    public func supervise(since: Date? = nil) -> AsyncThrowingStream<SupervisorEvent, Error> {
        let adapter = self.adapter
        let policy = backoffPolicy

        return AsyncThrowingStream { continuation in
            let task = Task {
                var consecutiveFailures = 0
                var lastEventTime: Date? = since

                continuation.yield(.phaseChanged(.idle))

                while !Task.isCancelled {
                    // -- Connect --
                    continuation.yield(.phaseChanged(.connecting))

                    var streamConnected = false
                    do {
                        let stream = adapter.streamEvents(since: lastEventTime)
                        for try await envelope in stream {
                            try Task.checkCancellation()
                            if !streamConnected {
                                streamConnected = true
                                consecutiveFailures = 0
                                continuation.yield(.phaseChanged(.streaming))
                            }
                            lastEventTime = envelope.eventAt
                            continuation.yield(.dockerEvent(envelope))
                        }
                        // Stream ended cleanly — treat as disconnect and retry
                    } catch {
                        if Task.isCancelled {
                            continuation.yield(.phaseChanged(.stopped))
                            continuation.finish()
                            return
                        }
                    }

                    // Reset failures if we successfully connected and received events
                    if streamConnected {
                        consecutiveFailures = 0
                    }

                    // -- Disconnect --
                    let disconnectTime = Date()
                    consecutiveFailures += 1
                    continuation.yield(
                        .phaseChanged(.disconnected(at: disconnectTime, attempt: consecutiveFailures))
                    )

                    guard consecutiveFailures <= policy.maxRetries else {
                        continuation.yield(.phaseChanged(.exhausted(totalAttempts: consecutiveFailures)))
                        continuation.finish()
                        return
                    }

                    // -- Backoff --
                    let delay = policy.delay(forAttempt: consecutiveFailures - 1)
                    let delaySeconds = Double(delay.components.seconds)
                        + Double(delay.components.attoseconds) / 1e18
                    let backoffUntil = Date().addingTimeInterval(delaySeconds)
                    continuation.yield(
                        .phaseChanged(.backingOff(until: backoffUntil, attempt: consecutiveFailures))
                    )

                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        // Cancelled during backoff
                        continuation.yield(.phaseChanged(.stopped))
                        continuation.finish()
                        return
                    }

                    // -- Resync --
                    continuation.yield(.phaseChanged(.resyncing))
                    do {
                        let containers = try await adapter.listContainers()
                        let resyncTime = Date()
                        continuation.yield(.resyncCompleted(containers: containers, at: resyncTime))
                        lastEventTime = resyncTime
                    } catch {
                        if Task.isCancelled {
                            continuation.yield(.phaseChanged(.stopped))
                            continuation.finish()
                            return
                        }
                        // Resync failed — will retry on next loop iteration
                        // Don't increment consecutiveFailures for resync failures
                        continue
                    }
                }

                // Loop exited due to cancellation
                continuation.yield(.phaseChanged(.stopped))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
