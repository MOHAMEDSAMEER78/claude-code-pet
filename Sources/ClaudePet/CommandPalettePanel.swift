import AppKit
import SwiftUI

final class CommandPalettePanel: NSPanel {
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

    func resizeToFit(height: CGFloat) {
        var newFrame = frame
        let delta = newFrame.height - height
        newFrame.origin.y += delta
        newFrame.size.height = height
        setFrame(newFrame, display: true)
    }
}
