import AppKit
import SwiftUI

/// A floating, non-activating, all-Spaces overlay panel that hosts a pet.
/// Never steals focus and never shows a Dock/Cmd-Tab entry. Content-agnostic
/// so both single-pet (aggregate) and multi-pet (per-session) modes can
/// reuse it.
final class PetPanel: NSPanel {
    /// The screen Y where the panel's TOP edge should stay put as content
    /// grows/shrinks - keeps the pet's resting position stable while extra
    /// cards (activity card, permission bubble) extend the panel further
    /// down instead of pushing the sprite itself up or down.
    private var topAnchorY: CGFloat

    init(rootView: some View, origin: NSPoint? = nil, size: NSSize = NSSize(width: 220, height: 270)) {
        topAnchorY = 0
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: rootView)

        if let origin {
            setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let margin: CGFloat = 24
            let defaultOrigin = NSPoint(
                x: screen.visibleFrame.maxX - frame.width - margin,
                y: screen.visibleFrame.minY + margin
            )
            setFrameOrigin(defaultOrigin)
        }
        topAnchorY = frame.origin.y + frame.height
    }

    /// Called whenever the SwiftUI content's natural size changes (e.g. the
    /// permission bubble or activity card appears/disappears). Resizes the
    /// panel to fit exactly - never clip - so Allow/Deny buttons are always
    /// within the window's actual clickable bounds, not just visually drawn
    /// past its edge.
    func fitToContent(_ size: CGSize) {
        guard size.height > 1, abs(size.height - frame.height) > 0.5 else { return }
        let newHeight = ceil(size.height)
        var newY = topAnchorY - newHeight
        if let screen = NSScreen.main {
            newY = max(newY, screen.visibleFrame.minY)
        }
        setFrame(NSRect(x: frame.origin.x, y: newY, width: frame.width, height: newHeight), display: true)
    }

    // true + becomesKeyOnlyIfNeeded means the panel only becomes key when the
    // user actually interacts with a control (e.g. the Allow/Deny buttons),
    // not just from mouse movement/hover - still never steals focus passively.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Fades and slides the panel in from just below its resting position -
    /// used for "Wake Pet" and opening the activity tray so appearing reads
    /// as a deliberate pop-in instead of an instant snap.
    func animateIn(completion: (() -> Void)? = nil) {
        let restingFrame = frame
        var startFrame = restingFrame
        startFrame.origin.y -= 10
        alphaValue = 0
        setFrame(startFrame, display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(restingFrame, display: true)
        }, completionHandler: completion)
    }

    /// The inverse of animateIn: fades and slides down before actually
    /// hiding the window - used for "Tuck Away Pet" and closing the tray.
    func animateOut(completion: (() -> Void)? = nil) {
        let restingFrame = frame
        var endFrame = restingFrame
        endFrame.origin.y -= 10
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { completion?(); return }
            self.orderOut(nil)
            self.alphaValue = 1
            self.setFrame(restingFrame, display: false)
            completion?()
        })
    }

    /// Default bottom-right-anchored slot for the Nth panel in a horizontal
    /// row of multi-pet panels (right-to-left, newest closest to the corner).
    static func slotOrigin(index: Int, panelWidth: CGFloat = 220, margin: CGFloat = 24, gap: CGFloat = 12) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 0, y: 0) }
        let x = screen.visibleFrame.maxX - panelWidth - margin - CGFloat(index) * (panelWidth + gap)
        let y = screen.visibleFrame.minY + margin
        return NSPoint(x: x, y: y)
    }
}
