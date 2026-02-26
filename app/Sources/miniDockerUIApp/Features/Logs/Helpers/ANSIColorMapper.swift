import AppKit
import MiniDockerCore

/// Maps ANSI color/style types to AppKit `NSColor` and attributed string attributes.
enum ANSIColorMapper {
    // MARK: - Cached Fonts

    /// Pre-computed monospaced fonts for all bold/italic combinations.
    /// Must be accessed on the main thread (AppKit requirement).
    private nonisolated(unsafe) static let cachedFonts: [[NSFont]] = {
        let size: CGFloat = 12
        let regular = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
        let boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        // Indexed by [bold ? 1 : 0][italic ? 1 : 0]
        return [
            [regular, italic],
            [bold, boldItalic],
        ]
    }()

    // MARK: - Cached Palette Colors

    /// Pre-computed 256-color palette.
    private static let paletteColors: [NSColor] = (0 ... 255).map { makePaletteColor(UInt8($0)) }

    // MARK: - Color Mapping

    /// Resolve an ``ANSIColor`` to an `NSColor`.
    static func color(for ansiColor: ANSIColor, alpha: CGFloat = 1.0) -> NSColor {
        switch ansiColor {
        case let .standard(index):
            return standardColor(index, bright: false).withAlphaComponent(alpha)
        case let .bright(index):
            return standardColor(index, bright: true).withAlphaComponent(alpha)
        case let .palette(index):
            return paletteColors[Int(index)].withAlphaComponent(alpha)
        case let .rgb(r, g, b):
            return NSColor(
                srgbRed: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: alpha
            )
        }
    }

    // MARK: - Custom Attribute Keys

    /// Marker attribute indicating the foreground color is the default (no explicit ANSI color).
    /// Used by stderr rendering to reliably detect which spans need recoloring.
    static let isDefaultForegroundKey = NSAttributedString.Key("ANSIDefaultForeground")

    // MARK: - Attributed String Attributes

    /// Build attributed string attributes from an ``ANSIStyle``.
    static func attributes(
        for style: ANSIStyle,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: cachedFonts[style.isBold ? 1 : 0][style.isItalic ? 1 : 0],
        ]

        // Foreground color
        var fgColor: NSColor
        if let fg = style.foreground {
            fgColor = color(for: fg)
        } else {
            fgColor = .labelColor
            attrs[Self.isDefaultForegroundKey] = true
        }
        if style.isDim {
            fgColor = fgColor.withAlphaComponent(0.5)
        }
        attrs[.foregroundColor] = fgColor

        // Background color
        if let bg = style.background {
            attrs[.backgroundColor] = color(for: bg, alpha: 0.3)
        }

        // Underline
        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attrs
    }

    // MARK: - Private

    /// Map standard ANSI color index (0-7) to NSColor.
    /// Uses system semantic colors that automatically adapt to light/dark mode.
    private static func standardColor(_ index: UInt8, bright: Bool) -> NSColor {
        switch index {
        case 0: return bright ? .systemGray : .black
        case 1: return .systemRed
        case 2: return .systemGreen
        case 3: return .systemYellow
        case 4: return .systemBlue
        case 5: return .systemPurple
        case 6: return .systemTeal
        case 7: return bright ? .white : .lightGray
        default: return .labelColor
        }
    }

    /// Build a palette color for a given 256-color index (used once during cache init).
    private static func makePaletteColor(_ index: UInt8) -> NSColor {
        switch index {
        case 0 ... 7:
            return standardColor(index, bright: false)
        case 8 ... 15:
            return standardColor(index - 8, bright: true)
        case 16 ... 231:
            let adjusted = Int(index) - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return NSColor(
                srgbRed: r == 0 ? 0 : CGFloat(r * 40 + 55) / 255.0,
                green: g == 0 ? 0 : CGFloat(g * 40 + 55) / 255.0,
                blue: b == 0 ? 0 : CGFloat(b * 40 + 55) / 255.0,
                alpha: 1.0
            )
        default:
            let gray = CGFloat(Int(index - 232) * 10 + 8) / 255.0
            return NSColor(white: gray, alpha: 1.0)
        }
    }
}
