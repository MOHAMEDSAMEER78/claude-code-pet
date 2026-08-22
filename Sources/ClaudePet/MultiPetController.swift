import AppKit
import Combine
import SwiftUI
import ClaudePetCore

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

    func relayoutForScreenChange() {
        guard isActive else { return }
        reconcile(store.sessions)
    }

    private func reconcile(_ sessions: [EffectiveSession]) {
        let currentIds = Set(sessions.map(\.sessionId))

        for id in Array(panels.keys) where !currentIds.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            viewModels.removeValue(forKey: id)
        }

        for (index, session) in sessions.enumerated() {
            if let vm = viewModels[session.sessionId] {
                vm.update(with: session)
            } else {
                let pool = PetIdentity.namePool(customPetDirs: library.availableDirs)
                let key = PetIdentity.identityKey(
                    sessionId: session.sessionId, cwd: session.cwd,
                    groupByProject: AppSettings.shared.groupPetsByProject
                )
                let name = PetIdentity.name(for: key, pool: pool)
                let vm = SessionPetViewModel(session: session, identityName: name)
                viewModels[session.sessionId] = vm
                let origin = PetPanel.slotOrigin(index: index)
                var createdPanel: PetPanel?
                let view = SinglePetView(
                    viewModel: vm, library: library,
                    onSizeChange: { size in createdPanel?.fitToContent(size) },
                    onEndSession: { [weak store] in store?.killSession(sessionId: session.sessionId) }
                )
                let panel = PetPanel(rootView: view, origin: origin)
                createdPanel = panel
                panels[session.sessionId] = panel
                panel.orderFrontRegardless()
            }
        }

        for (index, session) in sessions.enumerated() {
            guard let panel = panels[session.sessionId] else { continue }
            let slotX = PetPanel.slotOrigin(index: index).x
            if abs(panel.frame.origin.x - slotX) > 0.5 {
                panel.setFrameOrigin(NSPoint(x: slotX, y: panel.frame.origin.y))
            }
        }
    }
}
