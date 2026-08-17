import AppKit
import Combine
import SwiftUI
import ClaudePetCore

/// Manages one floating PetPanel per active Claude Code session, adding and
/// removing panels as sessions come and go (SessionStore already handles
/// SessionEnd/TTL cleanup by dropping entries from `sessions`).
final class MultiPetController {
    private let store: SessionStore
    private let library: PetLibrary
    private var panels: [String: PetPanel] = [:]
    private var viewModels: [String: SessionPetViewModel] = [:]
    private var cancellable: AnyCancellable?
    private(set) var isActive = false

    init(store: SessionStore, library: PetLibrary) {
        self.store = store
        self.library = library
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        cancellable = store.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in self?.reconcile(sessions) }
    }

    func stop() {
        isActive = false
        cancellable = nil
        for (_, panel) in panels { panel.orderOut(nil) }
        panels.removeAll()
        viewModels.removeAll()
    }

    private func reconcile(_ sessions: [EffectiveSession]) {
        let currentIds = Set(sessions.map(\.sessionId))

        // Remove panels for sessions that disappeared.
        for id in Array(panels.keys) where !currentIds.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            viewModels.removeValue(forKey: id)
        }

        // Update existing / create new, in a stable left-to-right order.
        for (index, session) in sessions.enumerated() {
            if let vm = viewModels[session.sessionId] {
                vm.update(with: session)
            } else {
                let pool = PetIdentity.namePool(customPetDirs: library.availableDirs)
                let name = PetIdentity.name(for: session.sessionId, pool: pool)
                let vm = SessionPetViewModel(session: session, identityName: name)
                viewModels[session.sessionId] = vm
                let origin = PetPanel.slotOrigin(index: index)
                var createdPanel: PetPanel?
                let view = SinglePetView(
                    viewModel: vm, library: library,
                    onSizeChange: { size in createdPanel?.fitToContent(size) }
                )
                let panel = PetPanel(rootView: view, origin: origin)
                createdPanel = panel
                panels[session.sessionId] = panel
                panel.orderFrontRegardless()
            }
        }

        // Re-slot every panel by current order so departures close the gap.
        // Only the X position is fixed by slot index - Y is left alone since
        // fitToContent may have grown/repositioned a panel vertically to fit
        // a permission bubble or activity card.
        for (index, session) in sessions.enumerated() {
            guard let panel = panels[session.sessionId] else { continue }
            let slotX = PetPanel.slotOrigin(index: index).x
            if abs(panel.frame.origin.x - slotX) > 0.5 {
                panel.setFrameOrigin(NSPoint(x: slotX, y: panel.frame.origin.y))
            }
        }
    }
}
