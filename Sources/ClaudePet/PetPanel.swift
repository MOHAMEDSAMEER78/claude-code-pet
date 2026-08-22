import AppKit
import SwiftUI

final class PetPanel: NSPanel {
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
        } else {
            setFrameOrigin(Self.cornerOrigin(on: Self.targetScreen(), panelSize: frame.size, margin: 24))
        }
        topAnchorY = frame.origin.y + frame.height
    }

    static func targetScreen() -> NSScreen {
        if let id = AppSettings.shared.preferredScreenID,
           let match = NSScreen.screens.first(where: { screenID(for: $0) == id }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    static func screenID(for screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    static func cornerOrigin(on screen: NSScreen, panelSize: NSSize, margin: CGFloat) -> NSPoint {
        let frame = screen.visibleFrame
        let x: CGFloat
        let y: CGFloat
        switch AppSettings.shared.preferredCorner {
        case .bottomLeft:
            x = frame.minX + margin
            y = frame.minY + margin
        case .bottomRight:
            x = frame.maxX - panelSize.width - margin
            y = frame.minY + margin
        case .topLeft:
            x = frame.minX + margin
            y = frame.maxY - panelSize.height - margin
        case .topRight:
            x = frame.maxX - panelSize.width - margin
            y = frame.maxY - panelSize.height - margin
        }
        return NSPoint(x: x, y: y)
    }

    func fitToContent(_ size: CGSize) {
        guard size.height > 1, abs(size.height - frame.height) > 0.5 else { return }
        let newHeight = ceil(size.height)
        let newY = max(topAnchorY - newHeight, Self.targetScreen().visibleFrame.minY)
        setFrame(NSRect(x: frame.origin.x, y: newY, width: frame.width, height: newHeight), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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

    static func slotOrigin(index: Int, panelWidth: CGFloat = 220, margin: CGFloat = 24, gap: CGFloat = 12) -> NSPoint {
        let screen = targetScreen()
        let x = screen.visibleFrame.maxX - panelWidth - margin - CGFloat(index) * (panelWidth + gap)
        let y = screen.visibleFrame.minY + margin
        return NSPoint(x: x, y: y)
    }
}
