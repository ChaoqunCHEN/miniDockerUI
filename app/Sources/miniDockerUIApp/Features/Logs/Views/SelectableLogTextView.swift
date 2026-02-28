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
    var onIsAtBottomChanged: ((Bool) -> Void)?
    /// Incremented to trigger a scroll-to-bottom action.
    var scrollToBottomTrigger: Int = 0

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        // MARK: Rendered Content State

        /// Number of entries currently rendered in the text storage.
        var renderedEntryCount: Int = 0

        /// Character offset where each entry starts. Length = renderedEntryCount + 1.
        var entryOffsets: [Int] = [0]

        /// Identity of the first rendered entry for append-vs-rebuild detection.
        var firstEntryTimestamp: Date?
        var firstEntryMessage: String?

        // MARK: Scroll State

        /// Whether the user is scrolled to the bottom.
        var isAtBottom: Bool = true

        /// Tracks the last value of `scrollToBottomTrigger` to detect changes.
        var lastScrollToBottomTrigger: Int = 0

        /// Callback fired when the scroll position crosses the "at bottom" threshold.
        var onIsAtBottomChanged: ((Bool) -> Void)?

        // MARK: Search Highlight Cache

        /// Previous search highlight state to avoid redundant work.
        var lastHighlightedResultCount: Int = 0
        var lastHighlightedSelectedIndex: Int?
        var lastRenderedCountForHighlights: Int = 0

        /// Cached entry lookup dictionary, rebuilt only when entries change.
        var cachedEntryLookup: [EntryKey: Int] = [:]
        var cachedEntryLookupCount: Int = 0

        // MARK: Scrollbar Marker State

        /// The overlay view that draws match markers on the scrollbar track.
        var markerOverlay: ScrollbarMarkerOverlay?

        /// Handler forwarded to the overlay's `onMatchSelected`; set once in `makeNSView`
        /// and refreshed in `updateNSView`, avoiding per-cycle closure allocations on the overlay.
        var markerOverlayMatchHandler: ((Int) -> Void)?

        /// Cached marker positions to avoid O(N) layout queries per update cycle.
        var lastMarkerSearchResultCount: Int = 0
        var lastMarkerRenderedEntryCount: Int = 0

        /// Last overlay frame to avoid unnecessary AppKit frame assignments.
        var lastOverlayFrame: NSRect = .zero

        // MARK: Cache Invalidation

        /// Invalidate all search-related caches. Called when the rendered
        /// content changes (full rebuild or clear) so highlights and markers
        /// are recomputed on the next update cycle.
        func invalidateSearchCaches() {
            lastHighlightedResultCount = 0
            lastHighlightedSelectedIndex = nil
            lastRenderedCountForHighlights = 0
            lastMarkerSearchResultCount = 0
            lastMarkerRenderedEntryCount = 0
        }

        /// Reset all content-related state back to the empty state.
        func resetContentState() {
            renderedEntryCount = 0
            entryOffsets = [0]
            firstEntryTimestamp = nil
            firstEntryMessage = nil
            cachedEntryLookupCount = 0
            invalidateSearchCaches()
        }

        // MARK: Scroll Observation

        @MainActor @objc func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.enclosingScrollView,
                  let documentView = scrollView.documentView
            else { return }

            let viewportMaxY = clipView.bounds.maxY
            let documentHeight = documentView.frame.height
            let newIsAtBottom = viewportMaxY >= documentHeight - 20

            if newIsAtBottom != isAtBottom {
                isAtBottom = newIsAtBottom
                onIsAtBottomChanged?(newIsAtBottom)
            }
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

        let textView = ArrowCursorTextView()
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
        scrollView.documentCursor = NSCursor.arrow

        // Wire callback before registering the observer so it is never nil
        // when boundsDidChange fires.
        let coordinator = context.coordinator
        coordinator.onIsAtBottomChanged = onIsAtBottomChanged

        // Wire onMatchSelected through the coordinator once (not per-update).
        coordinator.markerOverlayMatchHandler = onMatchSelected

        // Observe scroll position
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Create scrollbar marker overlay. Frame is set in updateScrollbarMarkers
        // to align with the scroller's knobSlot.
        let overlay = ScrollbarMarkerOverlay(frame: .zero)
        overlay.isHidden = true
        overlay.onMatchSelected = { [weak coordinator] matchIndex in
            coordinator?.markerOverlayMatchHandler?(matchIndex)
        }
        scrollView.addSubview(overlay)
        coordinator.markerOverlay = overlay

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
        coordinator.onIsAtBottomChanged = onIsAtBottomChanged
        coordinator.markerOverlayMatchHandler = onMatchSelected

        let wasAtBottom = coordinator.isAtBottom
        let previousSelectedIndex = coordinator.lastHighlightedSelectedIndex

        updateTextContent(textStorage: textStorage, coordinator: coordinator)

        let entryLookup = searchResults.isEmpty ? [:] : buildEntryLookup(coordinator: coordinator)

        applySearchHighlights(textView: textView, coordinator: coordinator, entryLookup: entryLookup)

        updateScrollPosition(
            textView: textView,
            coordinator: coordinator,
            wasAtBottom: wasAtBottom,
            hasSelectedMatch: selectedResultIndex != nil
        )

        let matchSelectionChanged = selectedResultIndex != previousSelectedIndex
        if matchSelectionChanged {
            scrollToSelectedMatch(textView: textView, coordinator: coordinator, entryLookup: entryLookup)
        }

        updateScrollbarMarkers(scrollView: scrollView, coordinator: coordinator, entryLookup: entryLookup)
    }

    // MARK: - Scroll Position

    /// Handle explicit scroll-to-bottom triggers and auto-scroll when already at the bottom.
    private func updateScrollPosition(
        textView: NSTextView,
        coordinator: Coordinator,
        wasAtBottom: Bool,
        hasSelectedMatch: Bool
    ) {
        let triggerFired = scrollToBottomTrigger != coordinator.lastScrollToBottomTrigger

        if triggerFired {
            coordinator.lastScrollToBottomTrigger = scrollToBottomTrigger
            textView.scrollToEndOfDocument(nil)
            if !coordinator.isAtBottom {
                coordinator.isAtBottom = true
                // Defer @State mutation to avoid modifying state during the view update.
                DispatchQueue.main.async {
                    coordinator.onIsAtBottomChanged?(true)
                }
            }
        } else if wasAtBottom, coordinator.renderedEntryCount > 0, !hasSelectedMatch {
            // Auto-scroll to bottom only when no match is actively selected.
            textView.scrollToEndOfDocument(nil)
            coordinator.isAtBottom = true
        }
    }

    // MARK: - Text Content

    private func updateTextContent(
        textStorage: NSTextStorage,
        coordinator: Coordinator
    ) {
        let newCount = displayEntries.count

        // Clear all content when there are no entries to display.
        if newCount == 0 {
            if coordinator.renderedEntryCount > 0 {
                textStorage.setAttributedString(NSAttributedString())
                coordinator.resetContentState()
            }
            return
        }

        // Detect whether new entries were appended to an unchanged prefix.
        let isAppendOnly = coordinator.renderedEntryCount > 0
            && newCount >= coordinator.renderedEntryCount
            && displayEntries[0].timestamp == coordinator.firstEntryTimestamp
            && displayEntries[0].message == coordinator.firstEntryMessage

        // Nothing new -- skip entirely.
        if isAppendOnly, newCount == coordinator.renderedEntryCount {
            return
        }

        if isAppendOnly {
            appendNewEntries(textStorage: textStorage, coordinator: coordinator, from: coordinator.renderedEntryCount)
        } else {
            rebuildAllEntries(textStorage: textStorage, coordinator: coordinator)
        }

        coordinator.renderedEntryCount = newCount
    }

    /// Append entries starting at `startIndex` to existing text storage.
    private func appendNewEntries(
        textStorage: NSTextStorage,
        coordinator: Coordinator,
        from startIndex: Int
    ) {
        let newEntries = displayEntries[startIndex ..< displayEntries.count]
        var offsets = coordinator.entryOffsets
        let attrString = Self.buildAttributedString(for: newEntries, entryOffsets: &offsets)
        textStorage.beginEditing()
        textStorage.append(attrString)
        textStorage.endEditing()
        coordinator.entryOffsets = offsets
    }

    /// Replace the entire text storage with a fresh render of all entries.
    private func rebuildAllEntries(
        textStorage: NSTextStorage,
        coordinator: Coordinator
    ) {
        var offsets = [0]
        let attrString = Self.buildAttributedString(for: displayEntries[...], entryOffsets: &offsets)
        textStorage.beginEditing()
        textStorage.setAttributedString(attrString)
        textStorage.endEditing()
        coordinator.entryOffsets = offsets
        coordinator.firstEntryTimestamp = displayEntries[0].timestamp
        coordinator.firstEntryMessage = displayEntries[0].message
        coordinator.cachedEntryLookupCount = 0
        coordinator.invalidateSearchCaches()
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
            let isStderr = entry.stream == .stderr

            if let spans = entry.styledSpans {
                result.append(buildStyledEntry(spans: spans, isStderr: isStderr))
            } else {
                let attrs = isStderr ? stderrAttributes : stdoutAttributes
                result.append(NSAttributedString(string: entry.message + "\n", attributes: attrs))
            }

            let currentOffset = (entryOffsets.last ?? 0) + entry.message.utf16.count + 1
            entryOffsets.append(currentOffset)
        }

        return result
    }

    /// Build an attributed string for a single entry that has ANSI styled spans.
    private static func buildStyledEntry(
        spans: [ANSITextSpan],
        isStderr: Bool
    ) -> NSAttributedString {
        let entryStr = NSMutableAttributedString()

        for span in spans {
            let attrs = ANSIColorMapper.attributes(
                for: span.style,
                paragraphStyle: paragraphStyle
            )
            entryStr.append(NSAttributedString(string: span.text, attributes: attrs))
        }

        // For stderr, replace default foreground with red using the marker attribute
        if isStderr {
            let markerKey = ANSIColorMapper.isDefaultForegroundKey
            let fullRange = NSRange(location: 0, length: entryStr.length)
            entryStr.enumerateAttribute(markerKey, in: fullRange) { value, range, _ in
                if value != nil {
                    entryStr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                    entryStr.removeAttribute(markerKey, range: range)
                }
            }
        }

        let newlineAttrs = isStderr ? stderrAttributes : stdoutAttributes
        entryStr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        return entryStr
    }

    // MARK: - Entry Lookup

    private func buildEntryLookup(coordinator: Coordinator) -> [EntryKey: Int] {
        if coordinator.cachedEntryLookupCount == displayEntries.count,
           !coordinator.cachedEntryLookup.isEmpty
        {
            return coordinator.cachedEntryLookup
        }
        var lookup: [EntryKey: Int] = [:]
        lookup.reserveCapacity(displayEntries.count)
        for (i, entry) in displayEntries.enumerated() {
            let key = EntryKey(entry)
            if lookup[key] == nil {
                lookup[key] = i
            }
        }
        coordinator.cachedEntryLookup = lookup
        coordinator.cachedEntryLookupCount = displayEntries.count
        return lookup
    }

    // MARK: - Search Highlights

    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.45)
    private static let selectedColor = NSColor.systemOrange.withAlphaComponent(0.6)
    private static let selectedRowColor = NSColor.systemOrange.withAlphaComponent(0.15)

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
        let prevSelectedIdx = coordinator.lastHighlightedSelectedIndex

        // Skip if nothing changed
        if resultCount == coordinator.lastHighlightedResultCount,
           selectedIdx == prevSelectedIdx,
           coordinator.renderedEntryCount == coordinator.lastRenderedCountForHighlights
        {
            return
        }

        // Fast path: only the selected match index changed (no new results, no new entries)
        let selectionOnlyChanged = resultCount == coordinator.lastHighlightedResultCount
            && coordinator.renderedEntryCount == coordinator.lastRenderedCountForHighlights
            && resultCount > 0

        if selectionOnlyChanged {
            swapSelectedHighlight(
                layoutManager: layoutManager,
                textStorage: textStorage,
                coordinator: coordinator,
                entryLookup: entryLookup,
                oldSelectedIdx: prevSelectedIdx,
                newSelectedIdx: selectedIdx
            )
            coordinator.lastHighlightedSelectedIndex = selectedIdx
            return
        }

        // Full rebuild: clear and re-apply all highlights
        let fullRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        coordinator.lastHighlightedResultCount = resultCount
        coordinator.lastHighlightedSelectedIndex = selectedIdx
        coordinator.lastRenderedCountForHighlights = coordinator.renderedEntryCount

        guard !searchResults.isEmpty else { return }

        for (resultIdx, result) in searchResults.enumerated() {
            guard let (entryIdx, entryStart) = resolveEntryPosition(
                result: result, coordinator: coordinator, entryLookup: entryLookup
            ) else { continue }

            let isSelected = resultIdx == selectedIdx

            if isSelected {
                applySelectedRowHighlight(
                    layoutManager: layoutManager,
                    textStorage: textStorage,
                    coordinator: coordinator,
                    entryIdx: entryIdx,
                    entryStart: entryStart
                )
            }

            let color = isSelected ? Self.selectedColor : Self.matchColor
            applyMatchHighlights(
                layoutManager: layoutManager,
                textStorage: textStorage,
                result: result,
                entryStart: entryStart,
                color: color
            )
        }
    }

    /// Swap highlight colors between old and new selected matches without full redraw.
    private func swapSelectedHighlight(
        layoutManager: NSLayoutManager,
        textStorage: NSTextStorage,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int],
        oldSelectedIdx: Int?,
        newSelectedIdx: Int?
    ) {
        // De-select old match: remove row highlight, revert match color to yellow
        if let oldIdx = oldSelectedIdx, oldIdx < searchResults.count {
            let result = searchResults[oldIdx]
            if let (entryIdx, entryStart) = resolveEntryPosition(result: result, coordinator: coordinator, entryLookup: entryLookup) {
                let entryEnd = coordinator.entryOffsets[entryIdx + 1]
                let rowRange = NSRange(location: entryStart, length: entryEnd - entryStart)
                if rowRange.location + rowRange.length <= textStorage.length {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: rowRange)
                }
                applyMatchHighlights(
                    layoutManager: layoutManager,
                    textStorage: textStorage,
                    result: result,
                    entryStart: entryStart,
                    color: Self.matchColor
                )
            }
        }

        // Select new match: add row highlight, set match color to orange
        if let newIdx = newSelectedIdx, newIdx < searchResults.count {
            let result = searchResults[newIdx]
            if let (entryIdx, entryStart) = resolveEntryPosition(result: result, coordinator: coordinator, entryLookup: entryLookup) {
                applySelectedRowHighlight(
                    layoutManager: layoutManager,
                    textStorage: textStorage,
                    coordinator: coordinator,
                    entryIdx: entryIdx,
                    entryStart: entryStart
                )
                applyMatchHighlights(
                    layoutManager: layoutManager,
                    textStorage: textStorage,
                    result: result,
                    entryStart: entryStart,
                    color: Self.selectedColor
                )
            }
        }
    }

    /// Resolve a search result to its entry index and character offset, or `nil` if not found.
    private func resolveEntryPosition(
        result: LogSearchResult,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) -> (entryIdx: Int, entryStart: Int)? {
        guard let entryIdx = entryLookup[EntryKey(result.entry)],
              entryIdx + 1 < coordinator.entryOffsets.count
        else { return nil }
        return (entryIdx, coordinator.entryOffsets[entryIdx])
    }

    private func applySelectedRowHighlight(
        layoutManager: NSLayoutManager,
        textStorage: NSTextStorage,
        coordinator: Coordinator,
        entryIdx: Int,
        entryStart: Int
    ) {
        let entryEnd = coordinator.entryOffsets[entryIdx + 1]
        let rowRange = NSRange(location: entryStart, length: entryEnd - entryStart)
        if rowRange.location + rowRange.length <= textStorage.length {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: Self.selectedRowColor,
                forCharacterRange: rowRange
            )
        }
    }

    private func applyMatchHighlights(
        layoutManager: NSLayoutManager,
        textStorage: NSTextStorage,
        result: LogSearchResult,
        entryStart: Int,
        color: NSColor
    ) {
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

    // MARK: - Scrollbar Markers

    private static let markerOverlayWidth: CGFloat = 8

    private func updateScrollbarMarkers(
        scrollView: NSScrollView,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) {
        guard let overlay = coordinator.markerOverlay else { return }

        updateOverlayFrame(overlay: overlay, scrollView: scrollView, coordinator: coordinator)

        // Hide when no search results.
        guard !searchResults.isEmpty else {
            if !overlay.isHidden {
                overlay.isHidden = true
                overlay.matchPositions = []
                overlay.selectedMatchIndex = nil
            }
            return
        }

        overlay.isHidden = false

        // Only recompute positions when search results or entries changed.
        let needsPositionUpdate = searchResults.count != coordinator.lastMarkerSearchResultCount
            || coordinator.renderedEntryCount != coordinator.lastMarkerRenderedEntryCount

        if needsPositionUpdate {
            let positions = computeMarkerPositions(
                scrollView: scrollView, coordinator: coordinator, entryLookup: entryLookup
            )
            overlay.matchPositions = positions
            coordinator.lastMarkerSearchResultCount = searchResults.count
            coordinator.lastMarkerRenderedEntryCount = coordinator.renderedEntryCount
        }

        overlay.selectedMatchIndex = selectedResultIndex
    }

    /// Compute the overlay frame aligned with the scroller's knobSlot.
    /// Using the full scroll-view bounds causes markers to drift from the
    /// thumb -- the knobSlot is inset by ~3 px on each end for legacy
    /// scrollers, producing visible misalignment at extremes.
    private func updateOverlayFrame(
        overlay: ScrollbarMarkerOverlay,
        scrollView: NSScrollView,
        coordinator: Coordinator
    ) {
        let newFrame: NSRect
        if let scroller = scrollView.verticalScroller, scroller.knobProportion > 0 {
            let scrollerFrame = scroller.frame
            let knobSlot = scroller.rect(for: .knobSlot)
            newFrame = NSRect(
                x: scrollerFrame.origin.x,
                y: scrollerFrame.origin.y + knobSlot.origin.y,
                width: Self.markerOverlayWidth,
                height: knobSlot.height
            )
        } else {
            let svBounds = scrollView.bounds
            newFrame = NSRect(
                x: svBounds.width - Self.markerOverlayWidth,
                y: 0,
                width: Self.markerOverlayWidth,
                height: svBounds.height
            )
        }

        if newFrame != coordinator.lastOverlayFrame {
            overlay.frame = newFrame
            coordinator.lastOverlayFrame = newFrame
        }
    }

    /// Compute proportional Y positions (0..1) for each search result using the layout manager.
    private func computeMarkerPositions(
        scrollView: NSScrollView,
        coordinator: Coordinator,
        entryLookup: [EntryKey: Int]
    ) -> [CGFloat] {
        guard let textView = scrollView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return [] }

        let documentHeight = textView.frame.height
        let textLength = textView.textStorage?.length ?? 0
        guard documentHeight > 0, textLength > 0 else { return [] }

        let insetTop = textView.textContainerInset.height
        var positions: [CGFloat] = []
        positions.reserveCapacity(searchResults.count)

        for result in searchResults {
            guard let entryIdx = entryLookup[EntryKey(result.entry)],
                  entryIdx < coordinator.entryOffsets.count
            else {
                positions.append(0)
                continue
            }

            let charOffset = coordinator.entryOffsets[entryIdx]
            guard charOffset < textLength else {
                positions.append(1.0)
                continue
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: charOffset, length: 1),
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let proportion = (insetTop + rect.origin.y) / documentHeight
            positions.append(min(max(proportion, 0), 1))
        }

        return positions
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

        guard let (_, entryStart) = resolveEntryPosition(
            result: result, coordinator: coordinator, entryLookup: entryLookup
        ),
            let firstRange = result.matchRanges.first
        else { return }

        let nsRange = NSRange(firstRange, in: result.entry.message)
        let adjusted = NSRange(
            location: entryStart + nsRange.location,
            length: nsRange.length
        )

        textView.scrollRangeToVisible(adjusted)
        coordinator.isAtBottom = false
    }

    // MARK: - Entry Lookup Key

    struct EntryKey: Hashable {
        let timestamp: Date
        let message: String

        init(_ entry: LogEntry) {
            timestamp = entry.timestamp
            message = entry.message
        }
    }
}

// MARK: - Arrow Cursor Text View

/// NSTextView subclass that shows an arrow cursor instead of the I-beam,
/// since the log view is read-only.
///
/// NSTextView installs internal tracking areas (potentially with private
/// owner objects) that set the I-beam cursor through `mouseMoved:`.
/// We remove ALL tracking areas after super and install a single one owned
/// by self. This is safe because the view is non-editable (no IME needed)
/// and non-interactive beyond text selection.
private class ArrowCursorTextView: NSTextView {
    /// Reused tracking area — `.inVisibleRect` means the rect parameter is
    /// ignored, so the same instance works across all `updateTrackingAreas` calls.
    private lazy var arrowTrackingArea: NSTrackingArea = .init(
        rect: .zero,
        options: [.mouseMoved, .cursorUpdate, .mouseEnteredAndExited,
                  .activeInKeyWindow, .inVisibleRect],
        owner: self,
        userInfo: nil
    )

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove ALL tracking areas — including NSTextView's internal ones
        // that set the I-beam cursor via private helper objects.
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(arrowTrackingArea)
    }

    override func mouseMoved(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
    }
}
