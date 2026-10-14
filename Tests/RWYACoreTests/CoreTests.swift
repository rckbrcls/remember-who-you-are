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

    func testSkipPhrasesEscalate() {
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 0), SkipPhrases.regular[0])
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 3), SkipPhrases.streak)
    }
}
