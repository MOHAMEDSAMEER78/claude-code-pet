import Foundation

public enum TrayFilter: String, CaseIterable {
    case all
    case needsAttention
    case running

    public var label: String {
        switch self {
        case .all: return "All"
        case .needsAttention: return "Needs Attention"
        case .running: return "Running"
        }
    }
}

public enum TrayLogic {
    public static func matchesSearch(_ session: EffectiveSession, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        let haystack = [session.title, session.bubbleText, session.cwd]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(searchText.lowercased())
    }

    public static func matchesFilter(_ session: EffectiveSession, filter: TrayFilter) -> Bool {
        switch filter {
        case .all: return true
        case .running: return session.state == .running
        case .needsAttention: return session.state.priority >= PetState.review.priority
        }
    }

    public static func visibleSessions(_ sessions: [EffectiveSession], searchText: String, filter: TrayFilter) -> [EffectiveSession] {
        sessions
            .filter { matchesSearch($0, searchText: searchText) && matchesFilter($0, filter: filter) }
            .sorted { $0.state.priority > $1.state.priority }
    }

    public static func groupedByProject(_ sessions: [EffectiveSession], searchText: String, filter: TrayFilter) -> [(key: String, sessions: [EffectiveSession])] {
        let visible = sessions.filter { matchesSearch($0, searchText: searchText) && matchesFilter($0, filter: filter) }
        let groups = Dictionary(grouping: visible) { session -> String in
            guard let cwd = session.cwd, !cwd.isEmpty else { return "Other" }
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return name.isEmpty ? "Other" : name
        }
        return groups
            .map { (key: $0.key, sessions: $0.value.sorted { $0.state.priority > $1.state.priority }) }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.sessions.first?.state.priority ?? 0
                let rhsPriority = rhs.sessions.first?.state.priority ?? 0
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }
}
