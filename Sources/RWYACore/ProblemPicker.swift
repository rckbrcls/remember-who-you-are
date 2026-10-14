import Foundation

/// Picks problems at random without repeating the most recent ones.
public struct ProblemPicker {
    public var problems: [Problem]
    public var recentLimit: Int
    public private(set) var recent: [String]

    public init(problems: [Problem] = ProblemCatalog.all, recentLimit: Int = 10, recent: [String] = []) {
        self.problems = problems
        self.recentLimit = recentLimit
        self.recent = recent
    }

    public mutating func next(difficulties: Set<Difficulty> = Set(Difficulty.allCases),
                              excluding done: Set<String> = [],
                              using rng: inout some RandomNumberGenerator) -> Problem? {
        let pool = problems.filter { difficulties.contains($0.difficulty) && !done.contains($0.slug) }
        guard !pool.isEmpty else { return nil }
        // Never exhaust the pool through the recency filter.
        let limit = min(recentLimit, max(pool.count - 1, 0))
        let blocked = Set(recent.suffix(limit))
        let candidates = pool.filter { !blocked.contains($0.slug) }
        guard let pick = candidates.randomElement(using: &rng) else { return nil }
        recent.append(pick.slug)
        if recent.count > recentLimit { recent.removeFirst(recent.count - recentLimit) }
        return pick
    }

    public mutating func next(difficulties: Set<Difficulty> = Set(Difficulty.allCases),
                              excluding done: Set<String> = []) -> Problem? {
        var rng = SystemRandomNumberGenerator()
        return next(difficulties: difficulties, excluding: done, using: &rng)
    }
}
