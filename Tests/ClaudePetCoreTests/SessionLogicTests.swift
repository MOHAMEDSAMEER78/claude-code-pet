import Testing
@testable import ClaudePetCore

/// Uses swift-testing (bundled with the toolchain) rather than XCTest, since
/// XCTest.framework ships only with full Xcode - this keeps `swift test`
/// working on a CLT-only machine, matching the project's no-Xcode-required
/// build story.
struct SessionLogicTests {
    private func status(
        id: String = "s1", state: PetState = .running, ts: TimeInterval = 1000,
        cwd: String? = "/Users/dev/my-project", tool: String? = nil,
        summary: String? = nil, action: String? = nil
    ) -> SessionStatus {
        SessionStatus(
            sessionId: id, state: state, cwd: cwd, tool: tool, summary: summary,
            action: action, ts: ts, terminalPid: nil, terminalApp: nil, tty: nil,
            tasksDone: nil, tasksTotal: nil, title: nil, claudePid: nil
        )
    }

    // MARK: - effectiveState

    @Test func reviewDecaysToIdleAfterWindow() {
        let s = status(state: .review, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 1021, reviewDecaySeconds: 20)
        #expect(result == .idle)
    }

    @Test func reviewStaysReviewWithinWindow() {
        let s = status(state: .review, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 1010, reviewDecaySeconds: 20)
        #expect(result == .review)
    }

    @Test func nonReviewStatesNeverDecay() {
        let s = status(state: .failed, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 999_999, reviewDecaySeconds: 20)
        #expect(result == .failed)
    }

    // MARK: - isStale

    @Test func staleAfterThreshold() {
        let s = status(ts: 1000)
        #expect(SessionLogic.isStale(status: s, now: 1000 + 1801, staleSeconds: 1800))
        #expect(!SessionLogic.isStale(status: s, now: 1000 + 1799, staleSeconds: 1800))
    }

    // MARK: - bubbleText

    @Test func bubbleTextPrefersAction() {
        let s = status(cwd: "/x/my-project", tool: "Bash", summary: "npm test", action: "Running `npm test`")
        #expect(SessionLogic.bubbleText(for: s, state: .running) == "Running `npm test`")
    }

    @Test func bubbleTextFallsBackToCwdToolSummary() {
        let s = status(cwd: "/x/my-project", tool: "Bash", summary: "npm test", action: nil)
        #expect(SessionLogic.bubbleText(for: s, state: .running) == "my-project · Bash · npm test")
    }

    @Test func bubbleTextFallsBackToStateLabelWhenNothingElseAvailable() {
        let s = status(cwd: nil, tool: nil, summary: nil, action: nil)
        #expect(SessionLogic.bubbleText(for: s, state: .idle) == "Idle")
    }

    // MARK: - winner

    private func session(id: String, state: PetState, ts: TimeInterval) -> EffectiveSession {
        EffectiveSession(
            sessionId: id, state: state, bubbleText: "", cwd: nil, terminalPid: nil,
            terminalApp: nil, tty: nil, ts: ts, tasksDone: nil, tasksTotal: nil,
            title: nil, claudePid: nil
        )
    }

    @Test func winnerPicksHighestPriorityState() {
        let sessions = [
            session(id: "a", state: .idle, ts: 1),
            session(id: "b", state: .waitingPermission, ts: 2),
            session(id: "c", state: .failed, ts: 3),
        ]
        #expect(SessionLogic.winner(among: sessions)?.sessionId == "b")
    }

    @Test func winnerIsNilForEmptySessions() {
        #expect(SessionLogic.winner(among: []) == nil)
    }
}
