import Foundation
@testable import MiniDockerCore
import XCTest

final class ANSIParserTests: XCTestCase {
    // MARK: - No ANSI Codes

    func testPlainTextReturnsNilSpans() {
        let (stripped, spans) = ANSIParser.parse("Hello, world!")
        XCTAssertEqual(stripped, "Hello, world!")
        XCTAssertNil(spans)
    }

    func testEmptyStringReturnsNilSpans() {
        let (stripped, spans) = ANSIParser.parse("")
        XCTAssertEqual(stripped, "")
        XCTAssertNil(spans)
    }

    // MARK: - Single Color

    func testSingleGreenText() {
        let raw = "\u{1B}[32mHello\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Hello")
        XCTAssertNotNil(spans)
        XCTAssertEqual(spans?.count, 1)
        XCTAssertEqual(spans?[0].text, "Hello")
        XCTAssertEqual(spans?[0].style.foreground, .standard(2))
    }

    func testSingleRedText() {
        let raw = "\u{1B}[31mError\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Error")
        XCTAssertEqual(spans?.count, 1)
        XCTAssertEqual(spans?[0].style.foreground, .standard(1))
    }

    // MARK: - Multiple Colors

    func testMultipleColors() {
        let raw = "\u{1B}[31mRed\u{1B}[32mGreen\u{1B}[34mBlue\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "RedGreenBlue")
        XCTAssertEqual(spans?.count, 3)
        XCTAssertEqual(spans?[0].text, "Red")
        XCTAssertEqual(spans?[0].style.foreground, .standard(1))
        XCTAssertEqual(spans?[1].text, "Green")
        XCTAssertEqual(spans?[1].style.foreground, .standard(2))
        XCTAssertEqual(spans?[2].text, "Blue")
        XCTAssertEqual(spans?[2].style.foreground, .standard(4))
    }

    func testColorWithPlainText() {
        let raw = "prefix \u{1B}[33myellow\u{1B}[0m suffix"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "prefix yellow suffix")
        XCTAssertEqual(spans?.count, 3)
        XCTAssertEqual(spans?[0].text, "prefix ")
        XCTAssertFalse(spans?[0].style.hasAttributes ?? true)
        XCTAssertEqual(spans?[1].text, "yellow")
        XCTAssertEqual(spans?[1].style.foreground, .standard(3))
        XCTAssertEqual(spans?[2].text, " suffix")
    }

    // MARK: - Bright Colors

    func testBrightForegroundColors() {
        let raw = "\u{1B}[90mDim\u{1B}[91mBrightRed\u{1B}[97mBrightWhite\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "DimBrightRedBrightWhite")
        XCTAssertEqual(spans?[0].style.foreground, .bright(0))
        XCTAssertEqual(spans?[1].style.foreground, .bright(1))
        XCTAssertEqual(spans?[2].style.foreground, .bright(7))
    }

    func testBrightBackgroundColors() {
        let raw = "\u{1B}[100mBg\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Bg")
        XCTAssertEqual(spans?[0].style.background, .bright(0))
    }

    // MARK: - 256 Color

    func test256ColorForeground() {
        let raw = "\u{1B}[38;5;196mRed256\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Red256")
        XCTAssertEqual(spans?[0].style.foreground, .palette(196))
    }

    func test256ColorBackground() {
        let raw = "\u{1B}[48;5;21mBlueBg\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "BlueBg")
        XCTAssertEqual(spans?[0].style.background, .palette(21))
    }

    // MARK: - RGB Color

    func testRGBForeground() {
        let raw = "\u{1B}[38;2;255;128;0mOrange\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Orange")
        XCTAssertEqual(spans?[0].style.foreground, .rgb(255, 128, 0))
    }

    func testRGBBackground() {
        let raw = "\u{1B}[48;2;0;128;255mBlueBg\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "BlueBg")
        XCTAssertEqual(spans?[0].style.background, .rgb(0, 128, 255))
    }

    // MARK: - Text Attributes

    func testBoldText() {
        let raw = "\u{1B}[1mBold\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Bold")
        XCTAssertTrue(spans?[0].style.isBold ?? false)
    }

    func testDimText() {
        let raw = "\u{1B}[2mDim\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Dim")
        XCTAssertTrue(spans?[0].style.isDim ?? false)
    }

    func testItalicText() {
        let raw = "\u{1B}[3mItalic\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Italic")
        XCTAssertTrue(spans?[0].style.isItalic ?? false)
    }

    func testUnderlineText() {
        let raw = "\u{1B}[4mUnderline\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Underline")
        XCTAssertTrue(spans?[0].style.isUnderline ?? false)
    }

    func testBoldWithColor() {
        let raw = "\u{1B}[1;32mBoldGreen\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "BoldGreen")
        XCTAssertTrue(spans?[0].style.isBold ?? false)
        XCTAssertEqual(spans?[0].style.foreground, .standard(2))
    }

    // MARK: - Reset Codes

    func testResetClearsAllAttributes() {
        let raw = "\u{1B}[1;3;4;31mStyled\u{1B}[0mPlain"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "StyledPlain")
        XCTAssertEqual(spans?.count, 2)
        XCTAssertTrue(spans?[0].style.isBold ?? false)
        XCTAssertTrue(spans?[0].style.isItalic ?? false)
        XCTAssertTrue(spans?[0].style.isUnderline ?? false)
        XCTAssertFalse(spans?[1].style.hasAttributes ?? true)
    }

    func testEmptyParamsActsAsReset() {
        let raw = "\u{1B}[31mRed\u{1B}[mPlain"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "RedPlain")
        XCTAssertEqual(spans?[0].style.foreground, .standard(1))
        XCTAssertNil(spans?[1].style.foreground)
    }

    // MARK: - Background Colors

    func testStandardBackgroundColor() {
        let raw = "\u{1B}[41mRedBg\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "RedBg")
        XCTAssertEqual(spans?[0].style.background, .standard(1))
    }

    func testDefaultForegroundReset() {
        let raw = "\u{1B}[31mRed\u{1B}[39mDefault"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "RedDefault")
        XCTAssertEqual(spans?[0].style.foreground, .standard(1))
        XCTAssertNil(spans?[1].style.foreground)
    }

    func testDefaultBackgroundReset() {
        let raw = "\u{1B}[41mBg\u{1B}[49mNoBg"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "BgNoBg")
        XCTAssertEqual(spans?[0].style.background, .standard(1))
        XCTAssertNil(spans?[1].style.background)
    }

    // MARK: - Non-SGR Sequences

    func testNonSGRSequencesStripped() {
        // Cursor movement \e[2J (clear screen) and \e[H (cursor home)
        let raw = "\u{1B}[2J\u{1B}[HHello"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Hello")
        // Should have one plain span
        XCTAssertNil(spans) // single plain span returns nil
    }

    func testCursorMovementStripped() {
        let raw = "Line1\u{1B}[5ALine2"
        let (stripped, _) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Line1Line2")
    }

    // MARK: - Malformed Sequences

    func testIncompleteEscapeSequence() {
        // ESC at end of string
        let raw = "Hello\u{1B}"
        let (stripped, _) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Hello")
    }

    func testIncompleteCSISequence() {
        // ESC[ without terminator
        let raw = "Hello\u{1B}[32"
        let (stripped, _) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Hello")
    }

    func testLoneEscapeInMiddle() {
        let raw = "Hel\u{1B}lo"
        let (stripped, _) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "Hello")
    }

    // MARK: - ANSI-Only String

    func testANSIOnlyStringReturnsEmptyStripped() {
        let raw = "\u{1B}[32m\u{1B}[0m"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "")
        XCTAssertNil(spans)
    }

    // MARK: - Strip Convenience

    func testStripRemovesAllCodes() {
        let raw = "\u{1B}[1;31mError:\u{1B}[0m Something failed"
        let result = ANSIParser.strip(raw)
        XCTAssertEqual(result, "Error: Something failed")
    }

    // MARK: - Real-world Docker Log Patterns

    func testDockerTimestampWithColors() {
        // Simulated docker log with colored timestamp and level
        let raw = "\u{1B}[32m2024-01-15T10:30:00Z\u{1B}[0m \u{1B}[35mINFO\u{1B}[0m Server started"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "2024-01-15T10:30:00Z INFO Server started")
        XCTAssertNotNil(spans)
        XCTAssertEqual(spans?.count, 4)
        XCTAssertEqual(spans?[0].text, "2024-01-15T10:30:00Z")
        XCTAssertEqual(spans?[0].style.foreground, .standard(2)) // green
        XCTAssertEqual(spans?[1].text, " ")
        XCTAssertEqual(spans?[2].text, "INFO")
        XCTAssertEqual(spans?[2].style.foreground, .standard(5)) // magenta
        XCTAssertEqual(spans?[3].text, " Server started")
    }

    // MARK: - Attribute Reset Codes

    func testSelectiveReset() {
        let raw = "\u{1B}[1;3mBoldItalic\u{1B}[22mItalicOnly\u{1B}[23mPlain"
        let (stripped, spans) = ANSIParser.parse(raw)
        XCTAssertEqual(stripped, "BoldItalicItalicOnlyPlain")
        XCTAssertEqual(spans?.count, 3)
        XCTAssertTrue(spans?[0].style.isBold ?? false)
        XCTAssertTrue(spans?[0].style.isItalic ?? false)
        XCTAssertFalse(spans?[1].style.isBold ?? true)
        XCTAssertTrue(spans?[1].style.isItalic ?? false)
        XCTAssertFalse(spans?[2].style.isBold ?? true)
        XCTAssertFalse(spans?[2].style.isItalic ?? true)
    }

    // MARK: - Performance

    func testPerformanceLargeInputWithANSI() {
        // Build a string with ~100k chars and ANSI codes every ~50 chars
        var raw = ""
        let colors = [31, 32, 33, 34, 35, 36]
        for i in 0 ..< 2000 {
            let color = colors[i % colors.count]
            raw += "\u{1B}[\(color)m"
            raw += String(repeating: "x", count: 50)
            raw += "\u{1B}[0m"
        }

        measure {
            let (stripped, spans) = ANSIParser.parse(raw)
            XCTAssertEqual(stripped.count, 100_000)
            XCTAssertNotNil(spans)
        }
    }

    func testPerformancePlainTextFastPath() {
        let plain = String(repeating: "Hello world! This is a log line. ", count: 3125) // ~100k chars

        measure {
            let (stripped, spans) = ANSIParser.parse(plain)
            XCTAssertEqual(stripped.count, plain.count)
            XCTAssertNil(spans)
        }
    }
}
