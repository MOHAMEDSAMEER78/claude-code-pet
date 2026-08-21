import AppKit
import SwiftUI

/// A Spotlight-style floating panel: centered near the top third of the main
/// screen, takes keyboard focus (needed for the search field), closes itself
/// on Escape or when it loses key status.
final class CommandPalettePanel: NSPanel {
    // Tall enough to fit the search field, divider, and full session list
    // (up to the ScrollView's 260pt cap) without clipping on first appearance;
    // resizeToFit(height:) then shrinks it to the SwiftUI content's real size.
    private static let initialHeight: CGFloat = 340

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: Self.initialHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = NSHostingView(rootView: rootView.clipShape(RoundedRectangle(cornerRadius: 12)))

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - frame.width / 2
            let y = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.32
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { true }

    /// Resizes to the SwiftUI content's actual height, keeping the top edge
    /// fixed so the panel grows/shrinks downward like Spotlight.
    func resizeToFit(height: CGFloat) {
        var newFrame = frame
        let delta = newFrame.height - height
        newFrame.origin.y += delta
        newFrame.size.height = height
        setFrame(newFrame, display: true)
    }
}
