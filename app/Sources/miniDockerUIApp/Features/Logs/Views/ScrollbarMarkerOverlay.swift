import AppKit

/// Draws colored tick marks on a thin vertical strip to indicate
/// search match positions within the document, similar to VS Code / Xcode.
final class ScrollbarMarkerOverlay: NSView {
    // MARK: - Public Properties

    /// Proportional positions (0.0 = top, 1.0 = bottom) for each match.
    var matchPositions: [CGFloat] = [] {
        didSet { needsDisplay = true }
    }

    /// Index into matchPositions for the currently selected match.
    var selectedMatchIndex: Int? {
        didSet { needsDisplay = true }
    }

    /// Called when the user clicks near a marker. Passes the match index.
    var onMatchSelected: ((Int) -> Void)?

    // MARK: - Drawing Constants

    private static let markerHeight: CGFloat = 2
    private static let selectedMarkerHeight: CGFloat = 3
    private static let markerColor = NSColor.systemYellow.withAlphaComponent(0.85)
    private static let selectedMarkerColor = NSColor.systemOrange
    private static let backgroundColor = NSColor.gray.withAlphaComponent(0.08)
    private static let minimumPixelSpacing: CGFloat = 1

    // MARK: - Coordinate System

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Subtle background strip
        Self.backgroundColor.setFill()
        dirtyRect.fill()

        guard !matchPositions.isEmpty else { return }

        let trackHeight = bounds.height
        let trackWidth = bounds.width
        guard trackHeight > 0, trackWidth > 0 else { return }

        let markerH = Self.markerHeight

        // First pass: draw non-selected markers with deduplication
        Self.markerColor.setFill()
        var lastDrawnY: CGFloat = -.greatestFiniteMagnitude

        for (index, proportion) in matchPositions.enumerated() {
            if index == selectedMatchIndex { continue }

            let y = proportion * (trackHeight - markerH)

            // Skip if too close to previously drawn marker
            if y - lastDrawnY < Self.minimumPixelSpacing { continue }

            let rect = NSRect(x: 0, y: y, width: trackWidth, height: markerH)
            if rect.intersects(dirtyRect) {
                rect.fill()
            }
            lastDrawnY = y
        }

        // Second pass: draw selected marker on top (always visible)
        if let selIdx = selectedMatchIndex, selIdx < matchPositions.count {
            Self.selectedMarkerColor.setFill()
            let selH = Self.selectedMarkerHeight
            let y = matchPositions[selIdx] * (trackHeight - selH)
            NSRect(x: 0, y: y, width: trackWidth, height: selH).fill()
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard !matchPositions.isEmpty else {
            super.mouseDown(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        // isFlipped = true, so localPoint.y increases downward
        let clickProportion = localPoint.y / bounds.height

        // Find nearest match
        var nearestIndex = 0
        var nearestDistance: CGFloat = .greatestFiniteMagnitude

        for (index, position) in matchPositions.enumerated() {
            let distance = abs(position - clickProportion)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }

        // Only trigger if click is within ~20px of a marker
        let pixelThreshold: CGFloat = 20 / max(bounds.height, 1)
        if nearestDistance <= pixelThreshold {
            onMatchSelected?(nearestIndex)
        } else {
            super.mouseDown(with: event)
        }
    }
}
