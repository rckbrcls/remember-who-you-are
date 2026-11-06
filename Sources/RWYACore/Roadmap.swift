import Foundation

/// Where the next problem comes from.
public enum PracticeMode: String, CaseIterable, Identifiable, Sendable {
    case random, blind75, neetcode150
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .random: return "Random"
        case .blind75: return "Blind 75"
        case .neetcode150: return "NeetCode 150"
        }
    }
}

/// How a roadmap walks through its problems.
public enum RoadmapOrder: String, CaseIterable, Identifiable, Sendable {
    /// Finish one domain (easy → hard) before moving to the next.
    case domain
    /// All easy problems across domains first, then medium, then hard.
    case difficulty
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .domain: return "Domain by domain"
        case .difficulty: return "Easy → Medium → Hard"
        }
    }
}

public struct RoadmapStep: Equatable, Sendable {
    public let problem: Problem
    public let domain: String
}

/// An ordered list of problems, walked front to back skipping what's done.
public struct Roadmap: Sendable {
    public let steps: [RoadmapStep]
    public let domains: [String]

    public init(steps: [RoadmapStep]) {
        self.steps = steps
        var seen = Set<String>()
        domains = steps.map(\.domain).filter { seen.insert($0).inserted }
    }

    /// Returns nil for `.random`.
    public init?(mode: PracticeMode, order: RoadmapOrder, catalog: [Problem] = ProblemCatalog.all) {
        guard mode != .random else { return nil }
        let bySlug = Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let rank: [Difficulty: Int] = [.easy: 0, .medium: 1, .hard: 2]
        var steps: [(step: RoadmapStep, domainIndex: Int, position: Int)] = []
        for (domainIndex, domain) in RoadmapData.domains.enumerated() {
            for raw in domain.slugs {
                let inBlind = raw.hasPrefix("*")
                if mode == .blind75 && !inBlind { continue }
                let slug = inBlind ? String(raw.dropFirst()) : raw
                guard let problem = bySlug[slug] else { continue } // premium-only
                steps.append((RoadmapStep(problem: problem, domain: domain.name), domainIndex, steps.count))
            }
        }
        steps.sort { a, b in
            let ra = rank[a.step.problem.difficulty]!, rb = rank[b.step.problem.difficulty]!
            switch order {
            case .domain:
                if a.domainIndex != b.domainIndex { return a.domainIndex < b.domainIndex }
                if ra != rb { return ra < rb }
            case .difficulty:
                if ra != rb { return ra < rb }
                if a.domainIndex != b.domainIndex { return a.domainIndex < b.domainIndex }
            }
            return a.position < b.position
        }
        self.init(steps: steps.map(\.step))
    }

    /// The first unfinished step matching `difficulties`. Steps in `skipped` are passed over
    /// until nothing else is left, so skipping never dead-ends the roadmap.
    public func next(difficulties: Set<Difficulty>, done: Set<String>, skipped: Set<String> = []) -> RoadmapStep? {
        let open = steps.filter { difficulties.contains($0.problem.difficulty) && !done.contains($0.problem.slug) }
        return open.first { !skipped.contains($0.problem.slug) } ?? open.first
    }

    public func progress(done: Set<String>, domain: String? = nil) -> (done: Int, total: Int) {
        let scoped = steps.filter { domain == nil || $0.domain == domain }
        return (scoped.filter { done.contains($0.problem.slug) }.count, scoped.count)
    }
}
