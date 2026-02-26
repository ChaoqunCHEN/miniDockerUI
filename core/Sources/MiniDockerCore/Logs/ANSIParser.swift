import Foundation

/// Parses ANSI escape sequences from terminal output, extracting styled text spans.
///
/// Handles SGR (Select Graphic Rendition) sequences for colors and text attributes.
/// Non-SGR CSI sequences (cursor movement, clear screen, etc.) are stripped silently.
public enum ANSIParser {
    private static let esc: Character = "\u{1B}"

    /// Parse a raw string containing ANSI escape codes.
    ///
    /// - Parameter raw: The raw terminal output string.
    /// - Returns: A tuple of the stripped (clean) text and optional styled spans.
    ///   When no ANSI codes are present, `spans` is `nil` for efficiency.
    public static func parse(_ raw: String) -> (stripped: String, spans: [ANSITextSpan]?) {
        // Fast path: no escape character means no ANSI codes
        guard raw.contains(esc) else {
            return (raw, nil)
        }

        var spans: [ANSITextSpan] = []
        var currentStyle = ANSIStyle.plain
        var currentText = ""
        var stripped = ""
        stripped.reserveCapacity(raw.count)

        var index = raw.startIndex

        while index < raw.endIndex {
            let ch = raw[index]

            if ch == esc {
                // Check for CSI sequence: ESC [
                let nextIndex = raw.index(after: index)
                if nextIndex < raw.endIndex, raw[nextIndex] == "[" {
                    // Parse CSI sequence
                    let afterBracket = raw.index(after: nextIndex)
                    let (params, terminator, endIndex) = parseCSISequence(raw, from: afterBracket)

                    if terminator == "m" {
                        // SGR sequence — apply style changes
                        flushSpan(text: &currentText, style: currentStyle, spans: &spans)
                        applySGR(params: params, style: &currentStyle)
                    }
                    // Non-SGR CSI sequences are silently stripped
                    index = endIndex
                } else {
                    // Lone ESC or non-CSI escape — strip it
                    index = nextIndex
                }
            } else {
                currentText.append(ch)
                stripped.append(ch)
                index = raw.index(after: index)
            }
        }

        // Flush any remaining text
        flushSpan(text: &currentText, style: currentStyle, spans: &spans)

        // If we only got one plain span covering all text, return nil spans
        if spans.count == 1, !spans[0].style.hasAttributes {
            return (stripped, nil)
        }

        return (stripped, spans.isEmpty ? nil : spans)
    }

    /// Strip ANSI escape codes, returning only visible text.
    public static func strip(_ raw: String) -> String {
        parse(raw).stripped
    }

    // MARK: - Private

    /// Parse a CSI parameter sequence starting after `ESC[`.
    /// Returns the parameter bytes, the terminating character, and the index after the sequence.
    private static func parseCSISequence(
        _ str: String,
        from start: String.Index
    ) -> (params: [UInt8], terminator: Character, endIndex: String.Index) {
        var params: [UInt8] = []
        var currentParam: UInt16 = 0
        var hasParam = false
        var index = start

        while index < str.endIndex {
            let ch = str[index]
            let next = str.index(after: index)

            // Parameter bytes: digits and semicolons
            if ch >= "0", ch <= "9" {
                let digit = UInt16(ch.asciiValue! - 48)
                // Saturate at 1000 to prevent wrapping; later clamped to UInt8
                currentParam = min(currentParam &* 10 &+ digit, 1000)
                hasParam = true
                index = next
            } else if ch == ";" {
                params.append(hasParam ? UInt8(min(currentParam, 255)) : 0)
                currentParam = 0
                hasParam = false
                index = next
            } else if ch >= "\u{40}", ch <= "\u{7E}" {
                // Final byte — terminates the sequence
                if hasParam {
                    params.append(UInt8(min(currentParam, 255)))
                }
                return (params, ch, next)
            } else if ch >= "\u{20}", ch <= "\u{3F}" {
                // Intermediate bytes — continue parsing
                index = next
            } else {
                // Invalid — bail out
                break
            }
        }

        // Unterminated sequence — return what we have
        if hasParam {
            params.append(UInt8(min(currentParam, 255)))
        }
        return (params, "\0", index)
    }

    /// Flush accumulated text into a span if non-empty.
    private static func flushSpan(
        text: inout String,
        style: ANSIStyle,
        spans: inout [ANSITextSpan]
    ) {
        guard !text.isEmpty else { return }
        spans.append(ANSITextSpan(text: text, style: style))
        text = ""
    }

    /// Apply SGR parameters to the current style.
    private static func applySGR(params: [UInt8], style: inout ANSIStyle) {
        // Empty params or [0] both mean reset
        if params.isEmpty {
            style = .plain
            return
        }

        var i = 0
        while i < params.count {
            let code = params[i]
            switch code {
            case 0:
                style = .plain

            case 1:
                style.isBold = true

            case 2:
                style.isDim = true

            case 3:
                style.isItalic = true

            case 4:
                style.isUnderline = true

            case 22:
                style.isBold = false
                style.isDim = false

            case 23:
                style.isItalic = false

            case 24:
                style.isUnderline = false

            // Standard foreground colors 30–37
            case 30 ... 37:
                style.foreground = .standard(code - 30)

            // Default foreground
            case 39:
                style.foreground = nil

            // Standard background colors 40–47
            case 40 ... 47:
                style.background = .standard(code - 40)

            // Default background
            case 49:
                style.background = nil

            // Extended foreground color: 38;5;N or 38;2;R;G;B
            case 38:
                i += 1
                parseExtendedColor(params: params, index: &i, applyTo: &style.foreground)
                continue // index already advanced

            // Extended background color: 48;5;N or 48;2;R;G;B
            case 48:
                i += 1
                parseExtendedColor(params: params, index: &i, applyTo: &style.background)
                continue

            // Bright foreground colors 90–97
            case 90 ... 97:
                style.foreground = .bright(code - 90)

            // Bright background colors 100–107
            case 100 ... 107:
                style.background = .bright(code - 100)

            default:
                break
            }
            i += 1
        }
    }

    /// Parse extended color (256-color or RGB) from SGR parameters.
    private static func parseExtendedColor(
        params: [UInt8],
        index i: inout Int,
        applyTo color: inout ANSIColor?
    ) {
        guard i < params.count else { return }
        let mode = params[i]
        i += 1

        switch mode {
        case 5:
            // 256-color: 38;5;N
            guard i < params.count else { return }
            color = .palette(params[i])
            i += 1
        case 2:
            // RGB: 38;2;R;G;B
            guard i + 2 < params.count else { return }
            color = .rgb(params[i], params[i + 1], params[i + 2])
            i += 3
        default:
            break
        }
    }
}
