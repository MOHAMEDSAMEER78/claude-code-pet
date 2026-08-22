import AppKit
import Combine

/// Drives the single aggregate pet's Codex-like idiosyncrasies that aren't
/// tied to Claude Code's own state: a one-shot wave on wake, a one-shot jump
/// on click, and autonomous idle wandering that walks the pet to a new spot
/// along the screen's bottom edge and "sleeps" there - mirroring the
/// documented real-Codex behavior of pets wandering and settling at screen
/// edges when there's nothing to report.
///
/// Only wired to the single aggregate panel/mode. Multi-pet mode panels are
/// a ClaudePet-specific extension (real Codex is single-pet), and wandering
/// several independently would be visually chaotic, so it's skipped there.
final class PetAnimator: ObservableObject {
    @Published var overrideRow: String?

    /// Whether the pet is allowed to stroll on its own while idle. Backed by
    /// AppSettings (the single settings model) rather than its own
    /// UserDefaults key, so it shows up in Preferences too.
    var wanderEnabled: Bool {
        get { AppSettings.shared.wanderEnabled }
        set {
            AppSettings.shared.wanderEnabled = newValue
            if !newValue { cancelWander() }
        }
    }

    private weak var panel: PetPanel?
    private weak var store: SessionStore?
    private weak var library: PetLibrary?
    private var transientTimer: Timer?
    private var wanderScheduleTimer: Timer?
    private var wanderStepTimer: Timer?
    private var moveObserver: NSObjectProtocol?
    private var isProgrammaticMove = false
    private var suppressWanderUntil = Date.distantPast
    private var isWandering = false

    func attach(panel: PetPanel, store: SessionStore, library: PetLibrary? = nil) {
        self.panel = panel
        self.store = store
        self.library = library

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isProgrammaticMove else { return }
            // A real user drag: back off from wandering for a while so we
            // don't fight their placement.
            self.cancelWander()
            self.suppressWanderUntil = Date().addingTimeInterval(120)
        }

        wanderScheduleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.maybeStartIdleVariant()
        }
    }

    func triggerWave() { playTransient("waving", frames: 4) }
    func triggerJump() { playTransient("jumping", frames: 5) }

    private func playTransient(_ row: String, frames: Int, fps: Double = 8) {
        transientTimer?.invalidate()
        overrideRow = row
        let duration = Double(frames) / fps + 0.15
        transientTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.overrideRow = self.isWandering ? self.overrideRow : nil
        }
    }

    /// Every tick, either strolls to a new spot (existing wander) or - if
    /// the current pet supports the extra rows - plays a brief stretch/
    /// look-around in place, so idle isn't always the same walk-and-settle
    /// loop. Options with no asset support (or, for the emoji fallback, no
    /// matching visual branch) are simply left out of the pick.
    private func maybeStartIdleVariant() {
        guard wanderEnabled else { return }
        guard !isWandering, transientTimer == nil || !(transientTimer?.isValid ?? false) else { return }
        guard Date() > suppressWanderUntil else { return }
        guard store?.aggregate == .idle else { return }
        guard Bool.random() && Bool.random() else { return } // ~75% skip each tick, keeps it lazy

        // No custom asset -> emoji fallback, which has hand-drawn branches
        // for both variants; a custom asset needs the matching sprite row.
        let hasStretch = library?.current == nil || (library?.current?.hasRow("stretching") ?? false)
        let hasLook = library?.current == nil || (library?.current?.hasRow("looking-around") ?? false)

        var options: [() -> Void] = [{ [weak self] in self?.beginWanderLeg() }]
        if hasStretch { options.append { [weak self] in self?.playIdleTransient("stretching", fallbackFrames: 4, fallbackFps: 6) } }
        if hasLook { options.append { [weak self] in self?.playIdleTransient("looking-around", fallbackFrames: 3, fallbackFps: 5) } }
        options.randomElement()?()
    }

    private func playIdleTransient(_ row: String, fallbackFrames: Int, fallbackFps: Double) {
        let frameCount = library?.current?.frames(row: row)?.count ?? fallbackFrames
        let fps = library?.current?.fps ?? fallbackFps
        playTransient(row, frames: frameCount, fps: fps)
    }

    private func beginWanderLeg() {
        guard let panel else { return }
        let screen = PetPanel.targetScreen()
        let margin: CGFloat = 24
        let minX = screen.visibleFrame.minX + margin
        let maxX = screen.visibleFrame.maxX - panel.frame.width - margin
        guard maxX > minX else { return }
        let targetX = CGFloat.random(in: minX...maxX)
        let y = screen.visibleFrame.minY + margin
        let startX = panel.frame.origin.x
        guard abs(targetX - startX) > 40 else { return } // not worth a trip

        isWandering = true
        overrideRow = targetX > startX ? "running-right" : "running-left"

        let stepDuration: TimeInterval = 0.02
        let totalSteps = 90
        var step = 0
        wanderStepTimer?.invalidate()
        wanderStepTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self, let panel = self.panel else { timer.invalidate(); return }
            step += 1
            let progress = CGFloat(step) / CGFloat(totalSteps)
            let easedX = startX + (targetX - startX) * min(progress, 1)
            self.isProgrammaticMove = true
            panel.setFrameOrigin(NSPoint(x: easedX, y: y))
            self.isProgrammaticMove = false
            if step >= totalSteps {
                timer.invalidate()
                self.wanderStepTimer = nil
                self.isWandering = false
                self.overrideRow = nil // settle back to idle pose
            }
        }
    }

    private func cancelWander() {
        wanderStepTimer?.invalidate()
        wanderStepTimer = nil
        isWandering = false
        overrideRow = nil
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        transientTimer?.invalidate()
        wanderScheduleTimer?.invalidate()
        wanderStepTimer?.invalidate()
    }
}
