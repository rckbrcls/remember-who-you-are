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

    func testDailyGoalMetAndFocus() {
        let goal = DailyGoal(easy: 2, medium: 1)
        XCTAssertFalse(goal.isMet(doneToday: [.easy: 2]))
        XCTAssertTrue(goal.isMet(doneToday: [.easy: 3, .medium: 1]))
        XCTAssertFalse(DailyGoal().isMet(doneToday: [.easy: 5]), "no goal is never 'met'")
        XCTAssertEqual(goal.focus(selected: [.easy, .medium, .hard], doneToday: [.easy: 2]), [.medium])
        // Nothing selected has quota left → fall back to the selection.
        XCTAssertEqual(goal.focus(selected: [.hard], doneToday: [:]), [.hard])
    }

    func testDailyLogCountsPerDay() {
        var log = DailyLog()
        let cal = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        log.record("two-sum", on: today, calendar: cal)
        log.record("two-sum", on: today, calendar: cal) // duplicate ignored
        log.record("3sum", on: today, calendar: cal)
        log.record("lru-cache", on: yesterday, calendar: cal)
        let diff: (String) -> Difficulty? = { ["two-sum": .easy, "3sum": .medium, "lru-cache": .medium][$0] }
        XCTAssertEqual(log.counts(on: today, calendar: cal, difficultyOf: diff), [.easy: 1, .medium: 1])
    }

    func testReminderClockAgentNagsOncePerRun() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = ReminderClock(rules: ReminderRules(onAgent: true, agentDelay: 60), now: t0)
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(30), agentWorkingSince: t0, goalMet: false))
        XCTAssertEqual(clock.evaluate(now: t0.addingTimeInterval(61), agentWorkingSince: t0, goalMet: false), .agent)
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(500), agentWorkingSince: t0, goalMet: false))
        // Agent stops, a new run starts: nags again.
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(600), agentWorkingSince: nil, goalMet: false))
        let run2 = t0.addingTimeInterval(700)
        XCTAssertEqual(clock.evaluate(now: run2.addingTimeInterval(60), agentWorkingSince: run2, goalMet: false), .agent)
    }

    func testReminderClockIntervalSnoozeAndGoal() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = ReminderClock(rules: ReminderRules(onAgent: false, onInterval: true, interval: 100), now: t0)
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(99), agentWorkingSince: nil, goalMet: false))
        XCTAssertEqual(clock.evaluate(now: t0.addingTimeInterval(100), agentWorkingSince: nil, goalMet: false), .interval)
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(150), agentWorkingSince: nil, goalMet: false))
        // Goal met: silent even when due.
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(300), agentWorkingSince: nil, goalMet: true))
        // Snoozed: silent until it ends, then nags.
        clock.snooze(until: t0.addingTimeInterval(1000))
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(900), agentWorkingSince: nil, goalMet: false))
        XCTAssertEqual(clock.evaluate(now: t0.addingTimeInterval(1000), agentWorkingSince: nil, goalMet: false), .interval)
        XCTAssertNil(clock.snoozedUntil)
        // Solving a problem resets the interval.
        clock.noteActivity(at: t0.addingTimeInterval(1050))
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(1120), agentWorkingSince: nil, goalMet: false))
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    func testStreakCountsConsecutiveDaysAndSurvivesUntilMidnight() {
        let cal = utc
        let noon = Date(timeIntervalSince1970: Double(1_800_000_000 - 1_800_000_000 % 86_400) + 12 * 3600)
        func day(_ offset: Int) -> Date { noon.addingTimeInterval(Double(offset) * 86_400) }
        var log = DailyLog()
        for o in [-10, -9, -8, -7] { log.record("p\(o)", on: day(o), calendar: cal) } // old run of 4
        for o in [-3, -2, -1] { log.record("q\(o)", on: day(o), calendar: cal) }      // current run of 3
        var s = Streak(log: log, now: day(0), calendar: cal)
        XCTAssertEqual(s.current, 3)
        XCTAssertFalse(s.doneToday)
        XCTAssertTrue(s.atRisk)
        XCTAssertEqual(s.best, 4)

        log.record("today", on: day(0), calendar: cal)
        s = Streak(log: log, now: day(0), calendar: cal)
        XCTAssertEqual(s.current, 4)
        XCTAssertFalse(s.atRisk)

        // A missed day breaks it.
        s = Streak(log: log, now: day(2), calendar: cal)
        XCTAssertEqual(s.current, 0)
        XCTAssertFalse(s.atRisk)
    }

    func testStreakWarningEscalatesTowardMidnight() {
        let cal = utc
        let midnight = Date(timeIntervalSince1970: Double(1_800_000_000 - 1_800_000_000 % 86_400))
        func at(_ h: Int, _ m: Int = 0) -> Date { midnight.addingTimeInterval(Double(h * 3600 + m * 60)) }
        XCTAssertNil(Streak.warningInterval(at: at(19, 59), warnFromHour: 20, calendar: cal))
        XCTAssertEqual(Streak.warningInterval(at: at(20), warnFromHour: 20, calendar: cal), 3600)
        XCTAssertEqual(Streak.warningInterval(at: at(22, 10), warnFromHour: 20, calendar: cal), 1800)
        XCTAssertEqual(Streak.warningInterval(at: at(23, 50), warnFromHour: 20, calendar: cal), 900)
        XCTAssertEqual(Streak.timeLeft(at: at(23, 50), calendar: cal), 600)
    }

    func testReminderClockStreakNagsRepeatAtInterval() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = ReminderClock(rules: ReminderRules(onAgent: false), now: t0)
        XCTAssertEqual(clock.evaluate(now: t0, agentWorkingSince: nil, goalMet: false, streakWarning: 900), .streak)
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(899), agentWorkingSince: nil, goalMet: false, streakWarning: 900))
        XCTAssertEqual(clock.evaluate(now: t0.addingTimeInterval(900), agentWorkingSince: nil, goalMet: false, streakWarning: 900), .streak)
        clock.snooze(until: t0.addingTimeInterval(2000))
        XCTAssertNil(clock.evaluate(now: t0.addingTimeInterval(1900), agentWorkingSince: nil, goalMet: false, streakWarning: 900))
    }

    func testDailyLogHistoryNewestFirst() {
        let cal = utc
        let log = DailyLog(days: ["2026-11-04": ["two-sum"], "2026-11-06": ["3sum", "lru-cache"], "2026-11-05": []])
        let h = log.history(calendar: cal)
        XCTAssertEqual(h.map(\.slugs), [["3sum", "lru-cache"], ["two-sum"]])
        XCTAssertEqual(DailyLog.key(for: h[0].day, calendar: cal), "2026-11-06")
    }

    func testSkipPhrasesEscalate() {
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 0), SkipPhrases.regular[0])
        XCTAssertEqual(SkipPhrases.phrase(forSkipCount: 3), SkipPhrases.streak)
    }
}
