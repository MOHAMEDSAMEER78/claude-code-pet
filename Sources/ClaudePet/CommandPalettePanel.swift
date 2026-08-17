import AppKit
import SwiftUI

/// A Spotlight-style floating panel: centered near the top third of the main
/// screen, takes keyboard focus (needed for the search field), closes itself
/// on Escape or when it loses key status.
final class CommandPalettePanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 60),
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
}
