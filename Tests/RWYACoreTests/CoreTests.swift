import XCTest
@testable import RWYACore

final class CoreTests: XCTestCase {
    func testCatalogLoads() {
        XCTAssertGreaterThan(ProblemCatalog.all.count, 1000)
        XCTAssertTrue(ProblemCatalog.all.contains { $0.slug == "two-sum" })
    }

    func testCatalogSlugsAreUnique() {
        let slugs = ProblemCatalog.all.map(\.slug)
        XCTAssertEqual(slugs.count, Set(slugs).count)
    }

    func testPickerDoesNotRepeatRecent() {
        var picker = ProblemPicker(recentLimit: 5)
        var seen: [String] = []
        for _ in 0..<30 {
            let p = picker.next()!
            XCTAssertFalse(seen.suffix(5).contains(p.slug))
            seen.append(p.slug)
        }
    }

    func testPickerRespectsDifficultyAndDone() {
        var picker = ProblemPicker()
        let hard = ProblemCatalog.all.filter { $0.difficulty == .hard }.map(\.slug)
        for _ in 0..<20 { XCTAssertEqual(picker.next(difficulties: [.hard])?.difficulty, .hard) }
        XCTAssertNil(picker.next(difficulties: [.hard], excluding: Set(hard)))
    }

    func testPickerSinglePoolStillReturns() {
        var picker = ProblemPicker(problems: [ProblemCatalog.all[0]], recentLimit: 10)
        XCTAssertNotNil(picker.next())
        XCTAssertNotNil(picker.next())
    }

    func testDetectorNeedsConsecutiveHits() {
        var d = AgentDetector()
        let busy = [ProcessSample(command: "/usr/local/bin/claude", cpu: 30)]
        let quiet = [ProcessSample(command: "/usr/local/bin/claude", cpu: 0.1)]
        XCTAssertEqual(d.ingest(busy), .idle)
        if case .working(let a, _) = d.ingest(busy) { XCTAssertEqual(a, .claudeCode) } else { XCTFail() }
        d.ingest(quiet); d.ingest(quiet)
        if case .idle = d.state { XCTFail("should still be working") }
        XCTAssertEqual(d.ingest(quiet), .idle)
    }

    func testDetectorIgnoresUnrelated() {
        var d = AgentDetector()
        for _ in 0..<5 { d.ingest([ProcessSample(command: "/usr/bin/python3", cpu: 99)]) }
        XCTAssertEqual(d.state, .idle)
    }

    func testRoadmapSizes() {
        // 7 premium-only problems aren't in the free catalog.
        XCTAssertEqual(Roadmap(mode: .neetcode150, order: .domain)?.steps.count, 143)
        XCTAssertEqual(Roadmap(mode: .blind75, order: .domain)?.steps.count, 69)
        XCTAssertNil(Roadmap(mode: .random, order: .domain))
    }

    func testRoadmapDomainOrderGoesEasyToHardWithinDomain() {
        let map = Roadmap(mode: .neetcode150, order: .domain)!
        XCTAssertEqual(map.steps.first?.domain, "Arrays & Hashing")
        XCTAssertEqual(map.domains.first, "Arrays & Hashing")
        for domain in map.domains {
            let ranks = map.steps.filter { $0.domain == domain }.map { Difficulty.allCases.firstIndex(of: $0.problem.difficulty)! }
            XCTAssertEqual(ranks, ranks.sorted(), domain)
        }
    }

    func testRoadmapDifficultyOrderFinishesEasyFirst() {
        let map = Roadmap(mode: .blind75, order: .difficulty)!
        let ranks = map.steps.map { Difficulty.allCases.firstIndex(of: $0.problem.difficulty)! }
        XCTAssertEqual(ranks, ranks.sorted())
    }

    func testRoadmapNextSkipsDoneAndSkippedAndRespectsDifficulty() {
        let map = Roadmap(mode: .neetcode150, order: .domain)!
        let first = map.steps[0].problem.slug
        XCTAssertEqual(map.next(difficulties: [.easy, .medium, .hard], done: [])?.problem.slug, first)
        XCTAssertNotEqual(map.next(difficulties: [.easy, .medium, .hard], done: [first])?.problem.slug, first)
        XCTAssertNotEqual(map.next(difficulties: [.easy, .medium, .hard], done: [], skipped: [first])?.problem.slug, first)
        XCTAssertEqual(map.next(difficulties: [.hard], done: [])?.problem.difficulty, .hard)
        // Everything skipped still yields something.
        let all = Set(map.steps.map(\.problem.slug))
        XCTAssertNotNil(map.next(difficulties: [.easy, .medium, .hard], done: [], skipped: all))
        XCTAssertNil(map.next(difficulties: [.easy, .medium, .hard], done: all))
        XCTAssertEqual(map.progress(done: [first]).done, 1)
    }

    func testSkipPhrasesEscalate() {
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 0), SkipPhrases.regular[0])
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 3), SkipPhrases.streak)
    }
}
