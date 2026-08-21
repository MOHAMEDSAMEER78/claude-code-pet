import Foundation
import Testing
@testable import ClaudePetCore

struct TrayLogicTests {
    private func session(
        id: String, state: PetState = .idle, cwd: String? = nil, title: String? = nil
    ) -> EffectiveSession {
        EffectiveSession(
            sessionId: id, state: state, bubbleText: "", cwd: cwd, terminalPid: nil,
            terminalApp: nil, tty: nil, ts: 0, tasksDone: nil, tasksTotal: nil,
            title: title, claudePid: nil
        )
    }

    // MARK: - matchesSearch

    @Test func emptySearchMatchesEverything() {
        #expect(TrayLogic.matchesSearch(session(id: "a"), searchText: ""))
    }

    @Test func searchMatchesTitleCaseInsensitively() {
        let s = session(id: "a", title: "Fix Login Bug")
        #expect(TrayLogic.matchesSearch(s, searchText: "login"))
        #expect(!TrayLogic.matchesSearch(s, searchText: "signup"))
    }

    @Test func searchMatchesCwd() {
        let s = session(id: "a", cwd: "/Users/dev/my-project")
        #expect(TrayLogic.matchesSearch(s, searchText: "my-project"))
    }

    // MARK: - matchesFilter

    @Test func needsAttentionExcludesRunningAndIdle() {
        #expect(!TrayLogic.matchesFilter(session(id: "a", state: .running), filter: .needsAttention))
        #expect(!TrayLogic.matchesFilter(session(id: "a", state: .idle), filter: .needsAttention))
        #expect(TrayLogic.matchesFilter(session(id: "a", state: .review), filter: .needsAttention))
        #expect(TrayLogic.matchesFilter(session(id: "a", state: .failed), filter: .needsAttention))
        #expect(TrayLogic.matchesFilter(session(id: "a", state: .waitingPermission), filter: .needsAttention))
    }

    @Test func runningFilterOnlyMatchesRunning() {
        #expect(TrayLogic.matchesFilter(session(id: "a", state: .running), filter: .running))
        #expect(!TrayLogic.matchesFilter(session(id: "a", state: .idle), filter: .running))
    }

    // MARK: - visibleSessions

    @Test func visibleSessionsFiltersAndSortsByPriority() {
        let sessions = [
            session(id: "a", state: .idle),
            session(id: "b", state: .failed),
            session(id: "c", state: .running),
        ]
        let result = TrayLogic.visibleSessions(sessions, searchText: "", filter: .all)
        #expect(result.map(\.sessionId) == ["b", "c", "a"])
    }

    // MARK: - groupedByProject

    @Test func groupsSessionsByCwdBasename() {
        let sessions = [
            session(id: "a", cwd: "/Users/dev/project-a"),
            session(id: "b", cwd: "/Users/dev/project-b"),
            session(id: "c", cwd: "/Users/dev/project-a"),
        ]
        let groups = TrayLogic.groupedByProject(sessions, searchText: "", filter: .all)
        #expect(groups.count == 2)
        #expect(groups.first { $0.key == "project-a" }?.sessions.count == 2)
    }

    @Test func sessionsWithNoCwdGroupUnderOther() {
        let groups = TrayLogic.groupedByProject([session(id: "a", cwd: nil)], searchText: "", filter: .all)
        #expect(groups.first?.key == "Other")
    }

    @Test func groupsOrderedByMostUrgentSessionFirst() {
        let sessions = [
            session(id: "a", state: .idle, cwd: "/x/calm-project"),
            session(id: "b", state: .failed, cwd: "/x/urgent-project"),
        ]
        let groups = TrayLogic.groupedByProject(sessions, searchText: "", filter: .all)
        #expect(groups.first?.key == "urgent-project")
    }
}
