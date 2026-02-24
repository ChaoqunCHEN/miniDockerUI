import Foundation
import os

/// A bounded, thread-safe ring buffer that stores ``LogEntry`` instances
/// per container, enforcing configurable line and byte caps.
///
/// Thread safety via `OSAllocatedUnfairLock`, matching the project's
/// established concurrency pattern.
public final class LogRingBuffer: Sendable {
    // MARK: - Internal Types

    struct ContainerBuffer {
        var entries: [LogEntry?]
        var head: Int
        var count: Int
        var totalBytes: Int

        init(capacity: Int) {
            entries = [LogEntry?](repeating: nil, count: capacity)
            head = 0
            count = 0
            totalBytes = 0
        }
    }

    struct State {
        var buffers: [String: ContainerBuffer] = [:]
    }

    // MARK: - Properties

    private let _policy: LogBufferPolicy
    private let state: OSAllocatedUnfairLock<State>

    // MARK: - Initializer

    public init(policy: LogBufferPolicy) {
        _policy = policy
        state = OSAllocatedUnfairLock(initialState: State())
    }

    /// The buffer policy governing capacity and drop behavior.
    public var policy: LogBufferPolicy {
        _policy
    }

    // MARK: - Append

    /// Append a single log entry.
    /// - Returns: Number of entries evicted (0 if rejected or no eviction needed).
    @discardableResult
    public func append(_ entry: LogEntry) -> Int {
        state.withLock { s in
            Self.appendEntry(entry, into: &s, policy: _policy)
        }
    }

    /// Append a batch of log entries.
    /// - Returns: Total number of entries evicted across the batch.
    @discardableResult
    public func appendBatch(_ entries: [LogEntry]) -> Int {
        state.withLock { s in
            var total = 0
            for entry in entries {
                total += Self.appendEntry(entry, into: &s, policy: _policy)
            }
            return total
        }
    }

    // MARK: - Read

    /// All entries for a container, oldest first.
    public func entries(forContainer containerId: String) -> [LogEntry] {
        state.withLock { s in
            Self.readEntries(from: s, containerId: containerId)
        }
    }

    /// Entries for a container within a time range, oldest first.
    public func entries(forContainer containerId: String, from: Date?, to: Date?) -> [LogEntry] {
        state.withLock { s in
            Self.readEntries(from: s, containerId: containerId).filter { entry in
                if let f = from, entry.timestamp < f { return false }
                if let t = to, entry.timestamp > t { return false }
                return true
            }
        }
    }

    // MARK: - Counts

    public func lineCount(forContainer containerId: String) -> Int {
        state.withLock { $0.buffers[containerId]?.count ?? 0 }
    }

    public func byteCount(forContainer containerId: String) -> Int {
        state.withLock { $0.buffers[containerId]?.totalBytes ?? 0 }
    }

    public var totalLineCount: Int {
        state.withLock { $0.buffers.values.reduce(0) { $0 + $1.count } }
    }

    public var totalByteCount: Int {
        state.withLock { $0.buffers.values.reduce(0) { $0 + $1.totalBytes } }
    }

    /// The set of container IDs that have buffered entries.
    public var containerIds: Set<String> {
        state.withLock { Set($0.buffers.keys) }
    }

    // MARK: - Clear

    public func clear(containerId: String) {
        state.withLock { _ = $0.buffers.removeValue(forKey: containerId) }
    }

    public func clearAll() {
        state.withLock { $0.buffers.removeAll() }
    }

    // MARK: - Byte Cost

    /// Compute the byte cost of a single log entry.
    static func byteCost(of entry: LogEntry) -> Int {
        entry.message.utf8.count
            + entry.containerId.utf8.count
            + entry.engineContextId.utf8.count
            + 64
    }

    // MARK: - Private

    private static func appendEntry(
        _ entry: LogEntry,
        into s: inout State,
        policy: LogBufferPolicy
    ) -> Int {
        let capacity = policy.maxLinesPerContainer
        let cid = entry.containerId
        let cost = byteCost(of: entry)

        if s.buffers[cid] == nil {
            s.buffers[cid] = ContainerBuffer(capacity: capacity)
        }

        switch policy.dropStrategy {
        case .dropNewest, .blockProducer:
            guard let buf = s.buffers[cid] else { return 0 }
            if buf.count >= capacity || (buf.totalBytes + cost) > policy.maxBytesPerContainer {
                return 0
            }
        case .dropOldest:
            break
        }

        var evicted = 0
        if policy.dropStrategy == .dropOldest {
            while let buf = s.buffers[cid],
                  buf.count > 0,
                  buf.count >= capacity || (buf.totalBytes + cost) > policy.maxBytesPerContainer
            {
                evictOldest(containerId: cid, state: &s)
                evicted += 1
            }
        }

        guard var buf = s.buffers[cid] else { return evicted }
        let writeIndex = (buf.head + buf.count) % capacity
        buf.entries[writeIndex] = entry
        buf.count += 1
        buf.totalBytes += cost
        s.buffers[cid] = buf

        return evicted
    }

    private static func evictOldest(containerId: String, state s: inout State) {
        guard var buf = s.buffers[containerId], buf.count > 0 else { return }
        let capacity = buf.entries.count
        if let old = buf.entries[buf.head] {
            buf.totalBytes -= byteCost(of: old)
        }
        buf.entries[buf.head] = nil
        buf.head = (buf.head + 1) % capacity
        buf.count -= 1
        s.buffers[containerId] = buf
    }

    private static func readEntries(from s: State, containerId: String) -> [LogEntry] {
        guard let buf = s.buffers[containerId] else { return [] }
        let capacity = buf.entries.count
        var result: [LogEntry] = []
        result.reserveCapacity(buf.count)
        for i in 0 ..< buf.count {
            let index = (buf.head + i) % capacity
            if let entry = buf.entries[index] {
                result.append(entry)
            }
        }
        return result
    }
}
