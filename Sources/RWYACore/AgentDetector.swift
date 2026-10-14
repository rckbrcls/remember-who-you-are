import Foundation

public enum Agent: String, CaseIterable, Sendable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case cursor = "Cursor"

    /// Matches the executable basename (or path fragment for app bundles).
    func matches(_ command: String) -> Bool {
        let base = (command as NSString).lastPathComponent.lowercased()
        switch self {
        case .claudeCode: return base == "claude"
        case .codex: return base == "codex"
        case .cursor: return command.contains("/Cursor.app/") && base.hasPrefix("cursor")
        }
    }
}

public enum AgentState: Equatable, Sendable {
    case idle
    case working(Agent, since: Date)
}

/// Turns raw process samples into a stable working/idle state.
/// An agent counts as working after `requiredHits` consecutive samples above `cpuThreshold`,
/// and goes idle again after `requiredMisses` consecutive samples below it.
public struct AgentDetector {
    public var cpuThreshold: Double
    public var requiredHits: Int
    public var requiredMisses: Int
    public private(set) var state: AgentState = .idle
    private var hits = 0
    private var misses = 0

    public init(cpuThreshold: Double = 5, requiredHits: Int = 2, requiredMisses: Int = 3) {
        self.cpuThreshold = cpuThreshold
        self.requiredHits = requiredHits
        self.requiredMisses = requiredMisses
    }

    @discardableResult
    public mutating func ingest(_ samples: [ProcessSample], now: Date = Date()) -> AgentState {
        var busiest: (agent: Agent, cpu: Double)?
        for agent in Agent.allCases {
            let cpu = samples.filter { agent.matches($0.command) }.reduce(0) { $0 + $1.cpu }
            if cpu >= cpuThreshold, cpu > (busiest?.cpu ?? 0) { busiest = (agent, cpu) }
        }

        if let busiest {
            hits += 1; misses = 0
            if hits >= requiredHits, case .idle = state { state = .working(busiest.agent, since: now) }
            else if hits >= requiredHits, case .working(_, let since) = state { state = .working(busiest.agent, since: since) }
        } else {
            misses += 1; hits = 0
            if misses >= requiredMisses { state = .idle }
        }
        return state
    }
}
