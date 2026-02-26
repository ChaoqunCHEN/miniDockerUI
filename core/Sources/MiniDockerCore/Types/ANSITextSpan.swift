import Foundation

/// Represents an ANSI terminal color.
/// A `nil` value of `ANSIColor?` represents the default terminal color.
public enum ANSIColor: Sendable, Codable, Equatable {
    /// Standard colors 0–7 (black, red, green, yellow, blue, magenta, cyan, white).
    case standard(UInt8)
    /// Bright colors 0–7.
    case bright(UInt8)
    /// 256-color palette index 0–255.
    case palette(UInt8)
    /// 24-bit true color.
    case rgb(UInt8, UInt8, UInt8)
}

/// ANSI text styling attributes.
public struct ANSIStyle: Sendable, Codable, Equatable {
    public var foreground: ANSIColor?
    public var background: ANSIColor?
    public var isBold: Bool
    public var isDim: Bool
    public var isItalic: Bool
    public var isUnderline: Bool

    public init(
        foreground: ANSIColor? = nil,
        background: ANSIColor? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderline = isUnderline
    }

    /// A style with no attributes set.
    public static let plain = ANSIStyle()

    /// Whether this style has any non-default attributes.
    public var hasAttributes: Bool {
        foreground != nil || background != nil || isBold || isDim || isItalic || isUnderline
    }
}

/// A span of text with associated ANSI styling.
public struct ANSITextSpan: Sendable, Codable, Equatable {
    public let text: String
    public let style: ANSIStyle

    public init(text: String, style: ANSIStyle) {
        self.text = text
        self.style = style
    }
}
