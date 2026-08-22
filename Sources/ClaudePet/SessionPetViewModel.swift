import AppKit
import Combine
import ClaudePetCore

/// Per-session view model backing one multi-pet-mode panel. Also owns the
/// "click to focus terminal" action, which uses TerminalFocuser to select
/// the exact tab/window this session is running in (via its tty), not just
/// activate the app.
final class SessionPetViewModel: ObservableObject {
    let sessionId: String
    let identityName: String
    @Published var state: PetState
    @Published var bubbleText: String
    @Published var overrideRow: String?
    @Published var tasksDone: Int?
    @Published var tasksTotal: Int?
    @Published var title: String?
    var terminalPid: Int32?
    var terminalApp: String?
    var tty: String?
    var cwd: String?
    private var jumpTimer: Timer?

    init(session: EffectiveSession, identityName: String) {
        self.sessionId = session.sessionId
        self.identityName = identityName
        self.state = session.state
        self.bubbleText = session.bubbleText
        self.terminalPid = session.terminalPid
        self.terminalApp = session.terminalApp
        self.tty = session.tty
        self.cwd = session.cwd
        self.tasksDone = session.tasksDone
        self.tasksTotal = session.tasksTotal
        self.title = session.title
    }

    func update(with session: EffectiveSession) {
        state = session.state
        bubbleText = session.bubbleText
        terminalPid = session.terminalPid
        terminalApp = session.terminalApp
        tty = session.tty
        cwd = session.cwd
        tasksDone = session.tasksDone
        tasksTotal = session.tasksTotal
        title = session.title
    }

    /// Key used to resolve a per-project pet skin override - same key used
    /// for per-project naming/tray-grouping.
    var assetKey: String {
        PetIdentity.identityKey(sessionId: sessionId, cwd: cwd, groupByProject: true)
    }

    func focusTerminal() {
        TerminalFocuser.focus(terminalApp: terminalApp, terminalPid: terminalPid, tty: tty, cwd: cwd)
    }

    func triggerJump() {
        jumpTimer?.invalidate()
        overrideRow = "jumping"
        jumpTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.overrideRow = nil
        }
    }
}
