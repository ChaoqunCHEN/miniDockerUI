import AppKit
import MiniDockerCore
import SwiftUI

/// An `NSViewRepresentable` wrapping `NSTextView` inside `NSScrollView` to provide
/// native multi-line text selection for the log viewer.
struct SelectableLogTextView: NSViewRepresentable {
    let displayEntries: [LogEntry]
    let searchResults: [LogSearchResult]
    let selectedResultIndex: Int?
    var onMatchSelected: ((Int) -> Void)?

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        /// Number of entries currently rendered in the text storage.
        var renderedEntryCount: Int = 0

        /// Character offset where each entry starts. Length = renderedEntryCount + 1.
        var entryOffsets: [Int] = [0]

        /// Whether the user is scrolled to the bottom.
        var isAtBottom: Bool = true

        /// Identity of the first rendered entry for append-vs-rebuild detection.
        var firstEntryTimestamp: Date?
        var firstEntryMessage: String?

        /// Previous search highlight state to avoid redundant work.
        var lastHighlightedResultCount: Int = 0
        var lastHighlightedSelectedIndex: Int?
        var lastRenderedCountForHighlights: Int = 0

        func resetHighlightState() {
            lastHighlightedResultCount = 0
            lastHighlightedSelectedIndex = nil
            lastRenderedCountForHighlights = 0
        }

        /// The overlay view that draws match markers on the scrollbar track.
        var markerOverlay: ScrollbarMarkerOverlay?

        @MainActor @objc func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.enclosingScrollView,
                  let documentView = scrollView.documentView
            else { return }

            let viewportMaxY = clipView.bounds.maxY
            let documentHeight = documentView.frame.height
            isAtBottom = viewportMaxY >= documentHeight - 20
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Make

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Line wrapping at the text view width
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        // Auto-resize vertically
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView

        // Observe scroll position
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Create scrollbar marker overlay (pinned to right edge)
        let overlay = ScrollbarMarkerOverlay(frame: .zero)
        overlay.isHidden = true
        overlay.autoresizingMask = [.height, .minXMargin]
        scrollView.addSubview(overlay)
        context.coordinator.markerOverlay = overlay

        return scrollView
    }

    // MARK: - Dismantle

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: - Update

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage
        else { return }

        let coordinator = context.coordinator
        let wasAtBottom = coordinator.isAtBottom
        let previousSelectedIndex = coordinator.lastHighlightedSelectedIndex

        updateTextContent(textStorage: textStorage, coordinator: coordinator)

        let entryLookup = searchResults.isEmpty ? [:] : buildEntryLookup()

        applySearchHighlights(textView: textView, coordinator: coordinator, entryLookup: entryLookup)

        let matchSelectionChanged = selectedResultIndex != previousSelectedIndex
        let hasSelectedMatch = selectedResultIndex != nil

        // Auto-scroll to bottom only when no match is actively selected
        if wasAtBottom, coordinator.renderedEntryCount > 0, !hasSelectedMatch {
            textView.scrollToEndOfDocument(nil)
            coordinator.isAtBottom = true
        }

        if matchSelectionChanged {
            scrollToSelectedMatch(textView: textView, coordinator: coordinator, entryLookup: entryLookup)
        }

        updateScrollbarMarkers(scrollView: scrollView, coordinator: coordinator, entryLookup: entryLookup)
    }

    // MARK: - Text Content

    private func updateTextContent(
        textStorage: NSTextStorage,
        coordinator: Coordinator
    ) {
        let newCount = displayEntries.count

        if newCount == 0 {
            if coordinator.renderedEntryCount > 0 {
                textStorage.setAttributedString(NSAttributedString())
                coordinator.renderedEntryCount = 0
                coordinator.entryOffsets = [0]
                coordinator.firstEntryTimestamp = nil
                coordinator.firstEntryMessage = nil
                coordinator.resetHighlightState()
            }
            return
        }

        // Detect append-only vs full rebuild
        let isAppendOnly = coordinator.renderedEntryCount > 0
            && newCount >= coordinator.renderedEntryCount
            && displayEntries[0].timestamp == coordinator.firstEntryTimestamp
            && displayEntries[0].message == coordinator.firstEntryMessage

        if isAppendOnly, newCount == coordinator.renderedEntryCount {
            return
        }

        if isAppendOnly {
            let startIndex = coordinator.renderedEntryCount
            let newEntries = displayEntries[startIndex ..< newCount]
            var offsets = coordinator.entryOffsets
            let newAttrString = Self.buildAttributedString(
                for: newEntries,
                entryOffsets: &offsets
            )
            textStorage.beginEditing()
            textStorage.append(newAttrString)
            textStorage.endEditing()
            coordinator.entryOffsets = offsets
        } else {
            var offsets = [0]
            let attrString = Self.buildAttributedString(
                for: displayEntries[...],
                entryOffsets: &offsets
            )
            textStorage.beginEditing()
            textStorage.setAttributedString(attrString)
            textStorage.endEditing()
            coordinator.entryOffsets = offsets
            coordinator.firstEntryTimestamp = displayEntries[0].timestamp
            coordinator.firstEntryMessage = displayEntries[0].message
            coordinator.resetHighlightState()
        }

        coordinator.renderedEntryCount = newCount
    }

    // MARK: - Attributed String Building

    private static let fontSize: CGFloat = 12

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }()

    private static let stdoutAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle,
    ]

    private static let stderrAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
        .foregroundColor: NSColor.systemRed,
        .paragraphStyle: paragraphStyle,
    ]

    private static func buildAttributedString(
        for entries: ArraySlice<LogEntry>,
        entryOffsets: inout [Int]
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for entry in entries {
            let msgAttrs = entry.stream == .stderr ? stderrAttributes : stdoutAttributes
            let msgStr = NSAttributedString(string: entry.message + "\n", attributes: msgAttrs)

            result.append(msgStr)

            let currentOffset = (entryOffsets.last ?? 0) + msgStr.length
            entryOffsets.append(currentOffset)
        }

        return result
    }

    // MARK: - Entry Lookup

    private func buildEntryLookup() -> [EntryKey: Int] {
        var lookup: [EntryKey: Int] = [:]
        lookup.reserveCapacity(displayEntries.count)
        for (i, entry) in displayEntries.enumerated() {
            let key = EntryKey(entry)
            if lookup[key] == nil {
                lookup[key] = i
            }
        }
        return lookup
    }

    // MARK: - Search Highlights

    private func applySearchHighlights(
        textView: NSTextView,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) {
        guard let layoutManager = textView.layoutManager,
              let textStorage = textView.textStorage
        else { return }

        let resultCount = searchResults.count
        let selectedIdx = selectedResultIndex

        // Skip if nothing changed
        if resultCount == coordinator.lastHighlightedResultCount,
           selectedIdx == coordinator.lastHighlightedSelectedIndex,
           coordinator.renderedEntryCount == coordinator.lastRenderedCountForHighlights
        {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Clear previous temporary attributes
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        coordinator.lastHighlightedResultCount = resultCount
        coordinator.lastHighlightedSelectedIndex = selectedIdx
        coordinator.lastRenderedCountForHighlights = coordinator.renderedEntryCount

        guard !searchResults.isEmpty else { return }

        let matchColor = NSColor.systemYellow.withAlphaComponent(0.45)
        let selectedColor = NSColor.systemOrange.withAlphaComponent(0.6)
        let selectedRowColor = NSColor.systemOrange.withAlphaComponent(0.15)

        for (resultIdx, result) in searchResults.enumerated() {
            guard let entryIdx = entryLookup[EntryKey(result.entry)],
                  entryIdx + 1 < coordinator.entryOffsets.count
            else { continue }

            let entryStart = coordinator.entryOffsets[entryIdx]
            let isSelected = resultIdx == selectedIdx

            // Highlight the full row for the selected match
            if isSelected {
                let entryEnd = coordinator.entryOffsets[entryIdx + 1]
                let rowRange = NSRange(location: entryStart, length: entryEnd - entryStart)
                if rowRange.location + rowRange.length <= textStorage.length {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: selectedRowColor,
                        forCharacterRange: rowRange
                    )
                }
            }

            let color = isSelected ? selectedColor : matchColor

            for matchRange in result.matchRanges {
                let nsRange = NSRange(matchRange, in: result.entry.message)
                let adjusted = NSRange(
                    location: entryStart + nsRange.location,
                    length: nsRange.length
                )
                if adjusted.location + adjusted.length <= textStorage.length {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: color,
                        forCharacterRange: adjusted
                    )
                }
            }
        }
    }

    // MARK: - Scrollbar Markers

    private static let markerOverlayWidth: CGFloat = 8

    private func updateScrollbarMarkers(
        scrollView: NSScrollView,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) {
        guard let overlay = coordinator.markerOverlay else { return }

        // Align the overlay with the vertical scroller
        if let scroller = scrollView.verticalScroller {
            let scrollerFrame = scroller.frame
            overlay.frame = NSRect(
                x: scrollerFrame.origin.x,
                y: 0,
                width: Self.markerOverlayWidth,
                height: scrollerFrame.height
            )
        } else {
            let svBounds = scrollView.bounds
            overlay.frame = NSRect(
                x: svBounds.width - Self.markerOverlayWidth,
                y: 0,
                width: Self.markerOverlayWidth,
                height: svBounds.height
            )
        }

        // Hide when no search results
        guard !searchResults.isEmpty else {
            if !overlay.isHidden {
                overlay.isHidden = true
                overlay.matchPositions = []
                overlay.selectedMatchIndex = nil
            }
            return
        }

        overlay.isHidden = false

        let totalLength = coordinator.entryOffsets.last ?? 0
        guard totalLength > 0 else {
            overlay.matchPositions = []
            overlay.selectedMatchIndex = nil
            return
        }

        let totalLengthFloat = CGFloat(totalLength)
        var positions: [CGFloat] = []
        positions.reserveCapacity(searchResults.count)

        for result in searchResults {
            guard let entryIdx = entryLookup[EntryKey(result.entry)],
                  entryIdx < coordinator.entryOffsets.count
            else {
                positions.append(0)
                continue
            }

            let proportion = CGFloat(coordinator.entryOffsets[entryIdx]) / totalLengthFloat
            positions.append(min(max(proportion, 0), 1))
        }

        overlay.matchPositions = positions
        overlay.selectedMatchIndex = selectedResultIndex

        overlay.onMatchSelected = { [onMatchSelected] matchIndex in
            onMatchSelected?(matchIndex)
        }
    }

    // MARK: - Scroll to Selected Match

    private func scrollToSelectedMatch(
        textView: NSTextView,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) {
        guard let selectedIdx = selectedResultIndex,
              selectedIdx < searchResults.count
        else { return }

        let result = searchResults[selectedIdx]

        guard let idx = entryLookup[EntryKey(result.entry)],
              idx + 1 < coordinator.entryOffsets.count,
              let firstRange = result.matchRanges.first
        else { return }

        let entryStart = coordinator.entryOffsets[idx]
        let nsRange = NSRange(firstRange, in: result.entry.message)
        let adjusted = NSRange(
            location: entryStart + nsRange.location,
            length: nsRange.length
        )

        textView.scrollRangeToVisible(adjusted)
        coordinator.isAtBottom = false
    }

    // MARK: - Entry Lookup Key

    private struct EntryKey: Hashable {
        let timestamp: Date
        let message: String

        init(_ entry: LogEntry) {
            timestamp = entry.timestamp
            message = entry.message
        }
    }
}
