import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: PetPanel?
    private var hotKeyManager: HotKeyManager?
    private let store = SessionStore()
    private let library = PetLibrary()
    private let permissions = PermissionRequestStore()
    private let animator = PetAnimator()
    private lazy var multiPetController = MultiPetController(store: store, library: library, permissions: permissions)
    private var toggleMenuItem: NSMenuItem?
    private var multiSessionMenuItem: NSMenuItem?
    private var wanderMenuItem: NSMenuItem?
    private var trayPanel: PetPanel?
    private var trayResignObserver: NSObjectProtocol?

    private static let multiSessionDefaultsKey = "multiSessionMode"

    private var multiSessionMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.multiSessionDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.multiSessionDefaultsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar-only, no Dock icon

        var createdPanel: PetPanel?
        let panel = PetPanel(rootView: PetView(
            store: store, library: library, permissions: permissions, animator: animator,
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
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Claude Pet")
        }

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Tuck Away Pet (⌘⇧P)", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(toggleItem)
        self.toggleMenuItem = toggleItem
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
        menu.addItem(withTitle: "Next Pet", action: #selector(nextPet), keyEquivalent: "")
        menu.addItem(withTitle: "Use Emoji Pet", action: #selector(useEmojiPet), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Pets", action: #selector(reloadPets), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal Pets Folder", action: #selector(revealPetsFolder), keyEquivalent: "")
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
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
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
                    identityFor: { [weak self] sessionId in
                        guard let self else { return "Session" }
                        let pool = PetIdentity.namePool(customPetDirs: self.library.availableDirs)
                        return PetIdentity.name(for: sessionId, pool: pool)
                    },
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
        tray.orderFrontRegardless()
        tray.makeKey()
    }

    private func hideTray() {
        trayPanel?.orderOut(nil)
    }

    @objc private func toggleWander() {
        animator.wanderEnabled.toggle()
        wanderMenuItem?.state = animator.wanderEnabled ? .on : .off
    }

    @objc private func nextPet() {
        library.selectNext()
    }

    @objc private func useEmojiPet() {
        library.useEmoji()
    }

    @objc private func reloadPets() {
        library.reload()
    }

    @objc private func revealPetsFolder() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
