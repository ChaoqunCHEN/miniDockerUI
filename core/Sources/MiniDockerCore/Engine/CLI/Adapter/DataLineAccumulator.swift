import Foundation

/// Splits a stream of `Data` chunks into newline-delimited strings.
///
/// Partial lines are buffered until a newline arrives. Call ``flush()``
/// after the stream ends to recover any trailing content.
struct DataLineAccumulator: Sendable {
    private var buffer: String = ""

    /// Feed a chunk of data. Returns all complete lines found.
    mutating func feed(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        buffer.append(text)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex ..< newlineIndex])
            lines.append(line)
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
        }
        return lines
    }

    /// Returns any remaining partial line after the stream ends.
    mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer = ""
        return remaining
    }
}
