import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import Sparkle
import ClaudePetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    /// Started eagerly (`startingUpdater: true`) so background update checks
    /// begin at launch; the app stays ad-hoc signed/non-notarized, so this
    /// only smooths *subsequent* updates - Gatekeeper's first-run warning is
    /// unaffected. Sparkle verifies downloaded update packages against its
    /// own EdDSA keypair (SUPublicEDKey in Info.plist), not code signing.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var panel: PetPanel?
    private var hotKeyManager: HotKeyManager?
    private var paletteHotKeyManager: HotKeyManager?
    private let store = SessionStore()
    private let library = PetLibrary()
    private let permissions = PermissionRequestStore()
    private let animator = PetAnimator()
    private let settings = AppSettings.shared
    private let notifications = NotificationManager()
    private lazy var historyStore = SessionHistoryStore(sessionStore: store)
    private lazy var progressStore = PetProgressStore(sessionStore: store, historyStore: historyStore)
    private lazy var multiPetController = MultiPetController(store: store, library: library)
    private var toggleMenuItem: NSMenuItem?
    private var multiSessionMenuItem: NSMenuItem?
    private var wanderMenuItem: NSMenuItem?
    private var trayPanel: PetPanel?
    private var trayResignObserver: NSObjectProtocol?
    private var palettePanel: CommandPalettePanel?
    private var paletteResignObserver: NSObjectProtocol?
    private var preferencesWindow: NSWindow?
    private var statsWindow: NSWindow?
    private var galleryWindow: NSWindow?
    private var hookSetupWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var budgetDigestTimer: Timer?

    private static let hasOfferedHookSetupKey = "hasOfferedHookSetup"

    private var multiSessionMode: Bool {
        get { settings.multiSessionMode }
        set { settings.multiSessionMode = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar-only, no Dock icon

        _ = historyStore // start listening for session-end events immediately
        _ = progressStore

        var createdPanel: PetPanel?
        let panel = PetPanel(rootView: PetView(
            store: store, library: library, animator: animator, progressStore: progressStore,
            onOpenTray: { [weak self] in self?.toggleTray() },
            onSizeChange: { size in createdPanel?.fitToContent(size) }
        ))
        createdPanel = panel
        self.panel = panel
        animator.attach(panel: panel, store: store, library: library)

        setupStatusItem()
        applyMode()
        if !multiSessionMode { animator.triggerWave() } // greet on wake, like the real thing

        hotKeyManager = HotKeyManager { [weak self] in
            self?.toggleVisibility()
        }
        paletteHotKeyManager = HotKeyManager(
            keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.toggleCommandPalette()
        }

        notifications.requestAuthorization()
        wireAlerts()
        maybeOfferHookSetupOnFirstRun()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let panel = self.panel, !self.multiSessionMode {
                let origin = PetPanel.cornerOrigin(on: PetPanel.targetScreen(), panelSize: panel.frame.size, margin: 24)
                panel.setFrameOrigin(origin)
            }
            self.multiPetController.relayoutForScreenChange()
        }
    }

    // MARK: - Alerts (notifications, sound, menu-bar icon)

    /// Wires SessionStore/PermissionRequestStore events to the reliability
    /// features that don't depend on the pet panel being visible: a native
    /// notification, an optional sound cue, and the menu-bar icon's state.
    private func wireAlerts() {
        store.stateTransitions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] old, new in
                guard let self else { return }
                SoundPlayer.play(for: new.state)
                let name = new.title ?? "Claude Code"
                self.notifications.notifyStateChange(name: name, state: new.state, appIsActive: self.isPetVisible)
            }
            .store(in: &cancellables)

        store.$aggregate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateMenuBarIcon(for: state) }
            .store(in: &cancellables)

        var seenRequestIds: Set<String> = []
        permissions.$requestsBySession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in
                guard let self else { return }
                for (_, request) in requests where !seenRequestIds.contains(request.requestId) {
                    seenRequestIds.insert(request.requestId)
                    self.notifications.notifyPermissionNeeded(request: request)
                }
                seenRequestIds = seenRequestIds.intersection(requests.values.map(\.requestId))
            }
            .store(in: &cancellables)

        budgetDigestTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.checkBudgetAndDigest()
        }
        checkBudgetAndDigest()
    }

    /// Checked every 10 minutes (not event-driven - both a running daily
    /// budget and a weekly digest are about elapsed time, not any single
    /// session event) while the app is running.
    private func checkBudgetAndDigest() {
        checkWeeklyDigest()
        checkBudgetAlert()
    }

    private func checkWeeklyDigest() {
        guard settings.weeklyDigestEnabled else { return }
        let now = Date()
        guard let last = settings.lastDigestSentAt else {
            settings.lastDigestSentAt = now // baseline only - no digest for a week with no history yet
            return
        }
        guard now.timeIntervalSince(last) >= 7 * 24 * 3600 else { return }
        let stats = historyStore.loadStats(now: now)
        let costUSD = historyStore.loadDailyBuckets(days: 7, now: now).reduce(0) { $0 + $1.costUSD }
        notifications.notifyWeeklyDigest(
            sessions: stats.sessionsThisWeek, tasksCompleted: stats.tasksCompletedThisWeek,
            secondsWorked: stats.secondsWorkedThisWeek, costUSD: costUSD
        )
        settings.lastDigestSentAt = now
    }

    private func checkBudgetAlert() {
        guard settings.budgetAlertsEnabled, settings.dailyBudgetUSD > 0 else { return }
        let now = Date()
        if let last = settings.lastBudgetAlertDate, Calendar.current.isDate(last, inSameDayAs: now) { return }
        let recordedSpend = historyStore.todaysRecordedSpendUSD(now: now)
        let activeIds = store.sessions.map(\.sessionId)
        let threshold = settings.dailyBudgetUSD
        let notifications = self.notifications
        let settings = self.settings
        Task.detached(priority: .utility) {
            let liveSpend = activeIds.reduce(0.0) { $0 + (TranscriptUsage.totals(forSession: $1)?.estimatedCostUSD ?? 0) }
            let total = recordedSpend + liveSpend
            guard total >= threshold else { return }
            await MainActor.run {
                notifications.notifyBudgetExceeded(spendUSD: total, thresholdUSD: threshold)
                settings.lastBudgetAlertDate = now
            }
        }
    }

    /// "Is there already an on-screen surface showing this?" - a notification
    /// only earns its interruption when nothing else already would.
    private var isPetVisible: Bool {
        if multiSessionMode { return multiPetController.isActive }
        return panel?.isVisible ?? false
    }

    private func updateMenuBarIcon(for state: PetState) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: state.menuBarSymbol, accessibilityDescription: state.label
        )
        statusItem?.button?.contentTintColor = tintColor(for: state)
    }

    private func tintColor(for state: PetState) -> NSColor? {
        switch state {
        case .waitingPermission: return .systemOrange
        case .failed: return .systemRed
        case .review: return .systemGreen
        case .running, .idle: return nil // default menu-bar template tint
        }
    }

    private func maybeOfferHookSetupOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: Self.hasOfferedHookSetupKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasOfferedHookSetupKey)
        let alreadyWired = HookInstaller.diagnose().contains { $0.title.contains("wired") && $0.status == .ok }
        guard !alreadyWired else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.showOnboarding()
        }
    }

    @objc private func showOnboarding() {
        showUtilityWindow(&onboardingWindow, title: "Welcome to ClaudePet") {
            OnboardingView(onFinished: { [weak self] in
                self?.onboardingWindow?.close()
                self?.showHookSetup()
            })
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: PetState.idle.menuBarSymbol, accessibilityDescription: "Claude Pet")
        }

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: L("menu.tuckAway"), action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(toggleItem)
        self.toggleMenuItem = toggleItem
        menu.addItem(withTitle: L("menu.jumpToSession"), action: #selector(toggleCommandPalette), keyEquivalent: "")
        menu.addItem(.separator())
        let multiItem = NSMenuItem(title: L("menu.multiSessionPets"), action: #selector(toggleMultiSessionMode), keyEquivalent: "")
        multiItem.target = self
        menu.addItem(multiItem)
        self.multiSessionMenuItem = multiItem
        let wanderItem = NSMenuItem(title: L("menu.wanderWhenIdle"), action: #selector(toggleWander), keyEquivalent: "")
        wanderItem.target = self
        wanderItem.state = animator.wanderEnabled ? .on : .off
        menu.addItem(wanderItem)
        self.wanderMenuItem = wanderItem
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.petGallery"), action: #selector(showGallery), keyEquivalent: "")
        menu.addItem(withTitle: L("menu.sessionStats"), action: #selector(showStats), keyEquivalent: "")
        menu.addItem(withTitle: L("menu.hookSetup"), action: #selector(showHookSetup), keyEquivalent: "")
        menu.addItem(withTitle: L("menu.welcomeTour"), action: #selector(showOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: L("menu.preferences"), action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.checkForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu

        self.statusItem = item
    }

    private func applyMode() {
        multiSessionMenuItem?.state = multiSessionMode ? .on : .off
        if multiSessionMode {
            panel?.orderOut(nil)
            hideTray()
            multiPetController.start()
        } else {
            multiPetController.stop()
            panel?.orderFrontRegardless()
        }
        updateToggleTitle()
    }

    private func updateToggleTitle() {
        let visible = multiSessionMode ? multiPetController.isActive : (panel?.isVisible ?? false)
        toggleMenuItem?.title = visible ? L("menu.tuckAway") : L("menu.wakePet")
    }

    @objc private func toggleMultiSessionMode() {
        multiSessionMode.toggle()
        applyMode()
    }

    @objc private func toggleVisibility() {
        let wasVisible = multiSessionMode ? multiPetController.isActive : (panel?.isVisible ?? false)
        if multiSessionMode {
            multiPetController.isActive ? multiPetController.stop() : multiPetController.start()
        } else {
            guard let panel else { return }
            if panel.isVisible {
                hideTray() // the tray is anchored to the pet - don't leave it floating alone
                panel.animateOut()
            } else {
                panel.animateIn()
            }
        }
        if wasVisible == false { animator.triggerWave() } // waking up: greet
        updateToggleTitle()
    }

    /// "Select the pet to open the activity tray" - the real Codex UX for
    /// switching between concurrent chats/sessions, per learn.chatgpt.com/docs/pets.
    /// Only offered in single-pet mode; Multi-Session Pets already surfaces
    /// every session as its own panel, so a tray on top would be redundant.
    private func toggleTray() {
        guard !multiSessionMode else { return }
        if let trayPanel, trayPanel.isVisible {
            hideTray()
        } else {
            showTray()
        }
    }

    private func showTray() {
        guard let panel else { return }
        if trayPanel == nil {
            let tray = PetPanel(
                rootView: ActivityTrayView(
                    store: store,
                    identityFor: { [weak self] sessionId in self?.identityName(for: sessionId) ?? "Session" },
                    onSelect: { [weak self] session in
                        TerminalFocuser.focus(
                            terminalApp: session.terminalApp,
                            terminalPid: session.terminalPid,
                            tty: session.tty,
                            cwd: session.cwd
                        )
                        self?.hideTray()
                    }
                ),
                size: NSSize(width: 260, height: 300)
            )
            trayResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: tray, queue: .main
            ) { [weak self] _ in self?.hideTray() }
            trayPanel = tray
        }
        guard let tray = trayPanel else { return }
        repositionTray(tray, relativeTo: panel)
        // Attach as a child window so AppKit moves the tray in lockstep with
        // the pet at the window-server level - same frame, no lag. A
        // didMove-notification-based follow (the previous approach) only
        // repositions reactively after each tick, which visibly stutters
        // during a live drag.
        panel.addChildWindow(tray, ordered: .above)
        tray.animateIn { tray.makeKey() }
    }

    private func repositionTray(_ tray: PetPanel, relativeTo panel: PetPanel) {
        let origin = NSPoint(x: panel.frame.origin.x + panel.frame.width - 260, y: panel.frame.maxY + 8)
        tray.setFrameOrigin(origin)
    }

    private func hideTray() {
        if let trayPanel, let panel { panel.removeChildWindow(trayPanel) }
        trayPanel?.animateOut()
    }

    /// Shared by the tray and command palette: same pool, same key policy
    /// (per-session by default, per-project when Group Pets By Project is on).
    private func identityName(for sessionId: String) -> String {
        let pool = PetIdentity.namePool(customPetDirs: library.availableDirs)
        let cwd = store.sessions.first(where: { $0.sessionId == sessionId })?.cwd
        let key = PetIdentity.identityKey(sessionId: sessionId, cwd: cwd, groupByProject: settings.groupPetsByProject)
        return PetIdentity.name(for: key, pool: pool)
    }

    @objc private func toggleWander() {
        animator.wanderEnabled.toggle()
        wanderMenuItem?.state = animator.wanderEnabled ? .on : .off
    }

    // MARK: - Command palette

    @objc private func toggleCommandPalette() {
        if let palettePanel, palettePanel.isVisible {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    private func showCommandPalette() {
        if palettePanel == nil {
            let view = CommandPaletteView(
                store: store,
                identityFor: { [weak self] sessionId in self?.identityName(for: sessionId) ?? "Session" },
                onSelect: { [weak self] session in
                    TerminalFocuser.focus(
                        terminalApp: session.terminalApp, terminalPid: session.terminalPid,
                        tty: session.tty, cwd: session.cwd
                    )
                    self?.hideCommandPalette()
                },
                onCancel: { [weak self] in self?.hideCommandPalette() },
                onHeightChange: { [weak self] height in self?.palettePanel?.resizeToFit(height: height) }
            )
            let p = CommandPalettePanel(rootView: view)
            paletteResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: p, queue: .main
            ) { [weak self] _ in self?.hideCommandPalette() }
            palettePanel = p
        }
        palettePanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideCommandPalette() {
        palettePanel?.orderOut(nil)
    }

    // MARK: - Secondary windows (Preferences / Stats / Gallery / Hook Setup)

    @objc private func showPreferences() {
        showUtilityWindow(&preferencesWindow, title: "Preferences") {
            PreferencesView(settings: self.settings)
        }
    }

    @objc private func showStats() {
        showUtilityWindow(&statsWindow, title: "Session Stats") {
            StatsView(
                stats: self.historyStore.loadStats(),
                activeSessionIds: self.store.sessions.map(\.sessionId),
                decodeWarning: self.store.lastDecodeWarning,
                progress: self.historyStore.loadProgress(),
                dailyBuckets: self.historyStore.loadDailyBuckets(days: 14),
                projectTotals: self.historyStore.loadProjectTotals(),
                usage: ClaudeUsageStore.load()
            )
        }
    }

    @objc private func showGallery() {
        showUtilityWindow(&galleryWindow, title: "Pet Gallery") {
            let projectKeys = Set(self.store.sessions.map {
                PetIdentity.identityKey(sessionId: $0.sessionId, cwd: $0.cwd, groupByProject: true)
            }).sorted()
            PetGalleryView(library: self.library, projectKeys: projectKeys)
        }
    }

    @objc private func showHookSetup() {
        showUtilityWindow(&hookSetupWindow, title: "Hook Setup & Diagnostics") {
            HookSetupView()
        }
    }

    /// Every secondary window (Preferences, Stats, Gallery, Hook Setup) is a
    /// plain, regular, closable NSWindow hosting one SwiftUI view - not a
    /// PetPanel, since these are deliberately normal windows the user
    /// interacts with directly, not floating overlays.
    private func showUtilityWindow<Content: View>(
        _ slot: inout NSWindow?, title: String, @ViewBuilder content: () -> Content
    ) {
        // Content is rebuilt every time even if the window is reused, so
        // views like Stats (a point-in-time snapshot, not a live binding)
        // show fresh data on every reopen instead of whatever was true when
        // the window was first created.
        let window: NSWindow
        if let existing = slot {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            slot = window
        }
        window.contentView = NSHostingView(rootView: content())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
