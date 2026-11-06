import Foundation

/// How many problems of each difficulty to solve per day. All zeros means "no goal".
public struct DailyGoal: Equatable, Sendable {
    public var easy: Int
    public var medium: Int
    public var hard: Int

    public init(easy: Int = 0, medium: Int = 0, hard: Int = 0) {
        self.easy = easy; self.medium = medium; self.hard = hard
    }

    public var isActive: Bool { easy + medium + hard > 0 }

    public func target(_ d: Difficulty) -> Int {
        switch d {
        case .easy: return easy
        case .medium: return medium
        case .hard: return hard
        }
    }

    public func remaining(_ d: Difficulty, doneToday: [Difficulty: Int]) -> Int {
        max(target(d) - (doneToday[d] ?? 0), 0)
    }

    public func isMet(doneToday: [Difficulty: Int]) -> Bool {
        isActive && Difficulty.allCases.allSatisfy { remaining($0, doneToday: doneToday) == 0 }
    }

    /// Difficulties the user should be fed next: the selected ones that still have quota left today.
    /// Falls back to `selected` when there's no goal, it's met, or nothing selected has quota.
    public func focus(selected: Set<Difficulty>, doneToday: [Difficulty: Int]) -> Set<Difficulty> {
        guard isActive else { return selected }
        let open = selected.filter { remaining($0, doneToday: doneToday) > 0 }
        return open.isEmpty ? selected : open
    }
}

/// Which problems were marked done on which day ("yyyy-MM-dd" → slugs).
public struct DailyLog: Equatable, Sendable {
    public private(set) var days: [String: [String]]

    public init(days: [String: [String]] = [:]) { self.days = days }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func record(_ slug: String, on date: Date, calendar: Calendar = .current) {
        let key = Self.key(for: date, calendar: calendar)
        if days[key]?.contains(slug) == true { return }
        days[key, default: []].append(slug)
        // Keep two years: enough for any streak worth bragging about.
        if days.count > 730, let oldest = days.keys.sorted().first { days[oldest] = nil }
    }

    /// Parses a "yyyy-MM-dd" key back to the start of that day.
    public static func date(forKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Days with at least one problem, newest first.
    public func history(calendar: Calendar = .current) -> [(day: Date, slugs: [String])] {
        days.compactMap { key, slugs in
            guard !slugs.isEmpty, let day = Self.date(forKey: key, calendar: calendar) else { return nil }
            return (day, slugs)
        }
        .sorted { $0.day > $1.day }
    }

    public func counts(on date: Date, calendar: Calendar = .current,
                       difficultyOf: (String) -> Difficulty?) -> [Difficulty: Int] {
        var out: [Difficulty: Int] = [:]
        for slug in days[Self.key(for: date, calendar: calendar)] ?? [] {
            if let d = difficultyOf(slug) { out[d, default: 0] += 1 }
        }
        return out
    }
}

/// Consecutive days with at least one solved problem.
public struct Streak: Equatable, Sendable {
    /// Days in a row, counting today if something was solved, otherwise ending yesterday
    /// (the streak is still alive until midnight).
    public let current: Int
    public let best: Int
    public let doneToday: Bool

    /// Alive but nothing solved yet today: it ends at midnight.
    public var atRisk: Bool { current > 0 && !doneToday }

    public init(current: Int, best: Int, doneToday: Bool) {
        self.current = current; self.best = best; self.doneToday = doneToday
    }

    public init(log: DailyLog, now: Date, calendar: Calendar = .current) {
        let active = Set(log.days.filter { !$0.value.isEmpty }.keys)
        func key(_ offset: Int) -> String {
            DailyLog.key(for: calendar.date(byAdding: .day, value: -offset, to: now)!, calendar: calendar)
        }
        let doneToday = active.contains(key(0))
        var run = 0
        var offset = doneToday ? 0 : 1
        while active.contains(key(offset)) { run += 1; offset += 1 }

        // Best: longest run of consecutive keys anywhere in the log.
        var best = 0, length = 0
        var previous: Date?
        let parser = DateFormatter()
        parser.calendar = calendar; parser.timeZone = calendar.timeZone; parser.dateFormat = "yyyy-MM-dd"
        for k in active.sorted() {
            guard let day = parser.date(from: k) else { continue }
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous).map({ calendar.isDate($0, inSameDayAs: day) }) == true {
                length += 1
            } else {
                length = 1
            }
            best = max(best, length)
            previous = day
        }
        self.init(current: run, best: max(best, run), doneToday: doneToday)
    }

    /// How often to nag about a streak at risk at `now`: hourly from `warnFromHour`,
    /// every 30 min in the last two hours, every 15 min in the last hour. Nil before `warnFromHour`.
    public static func warningInterval(at now: Date, warnFromHour: Int, calendar: Calendar = .current) -> TimeInterval? {
        let hour = calendar.component(.hour, from: now)
        guard hour >= warnFromHour else { return nil }
        switch hour {
        case 23: return 15 * 60
        case 22: return 30 * 60
        default: return 60 * 60
        }
    }

    /// Time left until midnight.
    public static func timeLeft(at now: Date, calendar: Calendar = .current) -> TimeInterval {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return midnight.timeIntervalSince(now)
    }
}

/// When to nag.
public struct ReminderRules: Equatable, Sendable {
    /// Nag once per agent run, after it has been working this long (0 = as soon as it starts).
    public var onAgent: Bool
    public var agentDelay: TimeInterval
    /// Nag every `interval`, agent or not.
    public var onInterval: Bool
    public var interval: TimeInterval

    public init(onAgent: Bool = true, agentDelay: TimeInterval = 120, onInterval: Bool = false, interval: TimeInterval = 3600) {
        self.onAgent = onAgent; self.agentDelay = agentDelay; self.onInterval = onInterval; self.interval = interval
    }
}

public enum NagReason: Equatable, Sendable { case agent, interval, streak }

/// Decides when a reminder fires. Pure state so it can be tested without timers.
public struct ReminderClock: Sendable {
    public var rules: ReminderRules
    public var snoozedUntil: Date?
    /// Interval reminders count from here: launch, the last nag, or the last solved problem.
    public private(set) var anchor: Date
    public private(set) var naggedForAgentRun = false
    public private(set) var lastStreakNag: Date?

    public init(rules: ReminderRules, now: Date = Date(), snoozedUntil: Date? = nil) {
        self.rules = rules
        self.anchor = now
        self.snoozedUntil = snoozedUntil
    }

    public func isSnoozed(at now: Date) -> Bool { snoozedUntil.map { now < $0 } ?? false }

    /// Call on every tick. Returns a reason when a reminder should be shown now.
    /// `streakWarning` is how often to nag about a streak about to end (nil when it's safe).
    public mutating func evaluate(now: Date, agentWorkingSince: Date?, goalMet: Bool,
                                  streakWarning: TimeInterval? = nil) -> NagReason? {
        if agentWorkingSince == nil { naggedForAgentRun = false }
        if let until = snoozedUntil, now >= until { snoozedUntil = nil }
        // Goal met or snoozed: stay quiet. An agent run that started meanwhile still gets its nag later.
        if goalMet || isSnoozed(at: now) { return nil }

        // A streak about to die beats everything else, and gets louder as midnight nears.
        if let every = streakWarning {
            if lastStreakNag.map({ now.timeIntervalSince($0) >= every }) ?? true {
                lastStreakNag = now
                anchor = now
                return .streak
            }
        } else {
            lastStreakNag = nil
        }

        if rules.onAgent, let since = agentWorkingSince, !naggedForAgentRun,
           now.timeIntervalSince(since) >= rules.agentDelay {
            naggedForAgentRun = true
            anchor = now
            return .agent
        }
        if rules.onInterval, now.timeIntervalSince(anchor) >= rules.interval {
            anchor = now
            return .interval
        }
        return nil
    }

    /// The user just did something useful; give them a full interval before the next nag.
    public mutating func noteActivity(at now: Date) { anchor = now }

    public mutating func snooze(until date: Date?) { snoozedUntil = date }
}
