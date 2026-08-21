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
    private var cancellables: Set<AnyCancellable> = []

    private static let hasOfferedHookSetupKey = "hasOfferedHookSetup"

    private var multiSessionMode: Bool {
        get { settings.multiSessionMode }
        set { settings.multiSessionMode = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar-only, no Dock icon

        var createdPanel: PetPanel?
        let panel = PetPanel(rootView: PetView(
            store: store, library: library, animator: animator,
            onOpenTray: { [weak self] in self?.toggleTray() },
            onSizeChange: { size in createdPanel?.fitToContent(size) }
        ))
        createdPanel = panel
        self.panel = panel
        animator.attach(panel: panel, store: store)

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
        _ = historyStore // start listening for session-end events immediately
        wireAlerts()
        maybeOfferHookSetupOnFirstRun()
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
            self?.showHookSetup()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: PetState.idle.menuBarSymbol, accessibilityDescription: "Claude Pet")
        }

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Tuck Away Pet (⌘⇧P)", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(toggleItem)
        self.toggleMenuItem = toggleItem
        menu.addItem(withTitle: "Jump to Session… (⌘⇧K)", action: #selector(toggleCommandPalette), keyEquivalent: "")
        menu.addItem(.separator())
        let multiItem = NSMenuItem(title: "Multi-Session Pets", action: #selector(toggleMultiSessionMode), keyEquivalent: "")
        multiItem.target = self
        menu.addItem(multiItem)
        self.multiSessionMenuItem = multiItem
        let wanderItem = NSMenuItem(title: "Wander When Idle", action: #selector(toggleWander), keyEquivalent: "")
        wanderItem.target = self
        wanderItem.state = animator.wanderEnabled ? .on : .off
        menu.addItem(wanderItem)
        self.wanderMenuItem = wanderItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pet Gallery…", action: #selector(showGallery), keyEquivalent: "")
        menu.addItem(withTitle: "Session Stats…", action: #selector(showStats), keyEquivalent: "")
        menu.addItem(withTitle: "Hook Setup & Diagnostics…", action: #selector(showHookSetup), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Pet", action: #selector(quit), keyEquivalent: "q")
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
        toggleMenuItem?.title = visible ? "Tuck Away Pet (⌘⇧P)" : "Wake Pet (⌘⇧P)"
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
        let origin = NSPoint(x: panel.frame.origin.x + panel.frame.width - 260, y: panel.frame.maxY + 8)
        tray.setFrameOrigin(origin)
        tray.animateIn { tray.makeKey() }
    }

    private func hideTray() {
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
                onCancel: { [weak self] in self?.hideCommandPalette() }
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
                decodeWarning: self.store.lastDecodeWarning
            )
        }
    }

    @objc private func showGallery() {
        showUtilityWindow(&galleryWindow, title: "Pet Gallery") {
            PetGalleryView(library: self.library)
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
