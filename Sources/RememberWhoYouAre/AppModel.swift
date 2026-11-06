import SwiftUI
import AppKit
import ServiceManagement
import RWYACore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AgentState = .idle
    @Published private(set) var problem: Problem?
    @Published private(set) var skipCount = 0
    @Published private(set) var reminderDue = false
    @Published private(set) var doneCount: Int
    @Published private(set) var tagline = Taglines.random()

    @Published private(set) var doneToday: [Difficulty: Int] = [:]
    @Published private(set) var snoozedUntil: Date?
    @Published private(set) var streak = Streak(current: 0, best: 0, doneToday: false)
    /// True in the warning hours when nothing is solved yet today and there's a streak to lose.
    @Published private(set) var streakInDanger = false
    @AppStorage("streakWarnings") var streakWarnings = true
    @AppStorage("streakWarnFromHour") var streakWarnFromHour = 20

    @AppStorage("delayMinutes") var delayMinutes = 2 { didSet { rulesChanged() } }
    @AppStorage("remindOnAgent") var remindOnAgent = true { didSet { rulesChanged() } }
    @AppStorage("remindOnInterval") var remindOnInterval = false { didSet { rulesChanged() } }
    @AppStorage("intervalMinutes") var intervalMinutes = 60 { didSet { rulesChanged() } }
    @AppStorage("goalEasy") var goalEasy = 0 { didSet { goalChanged() } }
    @AppStorage("goalMedium") var goalMedium = 0 { didSet { goalChanged() } }
    @AppStorage("goalHard") var goalHard = 0 { didSet { goalChanged() } }
    @AppStorage("snoozedUntil") private var snoozedUntilStored: Double = 0
    @AppStorage("showTitleInMenuBar") var showTitleInMenuBar = false
    @AppStorage("reminderStyle") var reminderStyleRaw = ReminderStyle.center.rawValue
    @AppStorage("includeEasy") var includeEasy = true { didSet { filtersChanged() } }
    @AppStorage("includeMedium") var includeMedium = true { didSet { filtersChanged() } }
    @AppStorage("includeHard") var includeHard = false { didSet { filtersChanged() } }
    @AppStorage("practiceMode") var modeRaw = PracticeMode.random.rawValue { didSet { roadmapChanged() } }
    @AppStorage("roadmapOrder") var orderRaw = RoadmapOrder.domain.rawValue { didSet { roadmapChanged() } }

    /// The domain of the current problem when following a roadmap.
    @Published private(set) var domain: String?
    private var roadmap: Roadmap?
    /// Roadmap problems skipped this run; they come back once everything else is done.
    private var roadmapSkipped = Set<String>()

    private var detector = AgentDetector()
    private var picker = ProblemPicker()
    private var done: Set<String>
    private var timer: Timer?
    private let source: ProcessSource = PSProcessSource()
    private let reminderPanel = ReminderPanel()
    private var clock: ReminderClock
    private var nagReason: NagReason?
    private var log: DailyLog
    private static let problemBySlug = Dictionary(
        ProblemCatalog.all.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    private static let difficultyBySlug = problemBySlug.mapValues(\.difficulty)

    struct HistoryDay: Identifiable {
        let day: Date
        let problems: [Problem]
        var id: Date { day }
    }

    /// Problems marked done, grouped by day, newest first.
    var history: [HistoryDay] {
        log.history().map { entry in
            HistoryDay(day: entry.day, problems: entry.slugs.compactMap { Self.problemBySlug[$0] })
        }
    }

    var reminderStyle: ReminderStyle { ReminderStyle(rawValue: reminderStyleRaw) ?? .center }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "done") ?? []
        done = Set(saved)
        doneCount = saved.count
        log = DailyLog(days: UserDefaults.standard.dictionary(forKey: "dailyLog") as? [String: [String]] ?? [:])
        clock = ReminderClock(rules: ReminderRules())
        clock.rules = rules
        let stored = UserDefaults.standard.double(forKey: "snoozedUntil")
        if stored > Date().timeIntervalSince1970 {
            clock.snooze(until: Date(timeIntervalSince1970: stored))
            snoozedUntil = clock.snoozedUntil
        }
        roadmap = Roadmap(mode: mode, order: order)
        refreshToday()
        pickNext()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // `open -a "Remember Who You Are" --args --preview-reminder` shows the alert right away.
        if CommandLine.arguments.contains("--preview-reminder") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.previewReminder()
            }
        }
    }

    var goal: DailyGoal { DailyGoal(easy: goalEasy, medium: goalMedium, hard: goalHard) }
    var goalMet: Bool { goal.isMet(doneToday: doneToday) }
    var isSnoozed: Bool { snoozedUntil.map { Date() < $0 } ?? false }

    private var rules: ReminderRules {
        ReminderRules(onAgent: remindOnAgent, agentDelay: Double(delayMinutes) * 60,
                      onInterval: remindOnInterval, interval: Double(intervalMinutes) * 60)
    }

    /// Difficulties with a target today, with progress — what the goal row shows.
    var goalItems: [(difficulty: Difficulty, done: Int, target: Int)] {
        Difficulty.allCases.compactMap { d in
            let t = goal.target(d)
            return t > 0 ? (d, min(doneToday[d] ?? 0, t), t) : nil
        }
    }

    var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .random }
    var order: RoadmapOrder { RoadmapOrder(rawValue: orderRaw) ?? .domain }

    /// A binding that goes through the property setter, so `didSet` observers fire
    /// (AppStorage's own `$binding` writes UserDefaults directly and skips them).
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }

    func isIncluded(_ difficulty: Difficulty) -> Bool {
        switch difficulty {
        case .easy: return includeEasy
        case .medium: return includeMedium
        case .hard: return includeHard
        }
    }

    /// Toggles a difficulty, refusing to turn off the last one.
    func toggle(_ difficulty: Difficulty) {
        let on = !isIncluded(difficulty)
        if !on && difficulties.count == 1 { return }
        switch difficulty {
        case .easy: includeEasy = on
        case .medium: includeMedium = on
        case .hard: includeHard = on
        }
    }

    /// e.g. "Blind 75 · 12/69" — nil in random mode.
    var roadmapProgress: String? {
        guard let roadmap else { return nil }
        let p = roadmap.progress(done: done)
        return "\(mode.title) · \(p.done)/\(p.total)"
    }

    /// e.g. "Trees 3/11" — nil in random mode.
    var domainProgress: String? {
        guard let roadmap, let domain else { return nil }
        let p = roadmap.progress(done: done, domain: domain)
        return "\(domain) \(p.done)/\(p.total)"
    }

    var difficulties: Set<Difficulty> {
        var s = Set<Difficulty>()
        if includeEasy { s.insert(.easy) }
        if includeMedium { s.insert(.medium) }
        if includeHard { s.insert(.hard) }
        return s.isEmpty ? [.easy] : s
    }

    var difficultyLabel: String {
        [(includeEasy, "Easy"), (includeMedium, "Medium"), (includeHard, "Hard")]
            .filter { $0.0 }.map { $0.1 }.joined(separator: "/")
    }


    var menuBarEmoji: String {
        if goalMet { return "🏆" }
        if isSnoozed { return "😴" }
        if streakInDanger { return "⏳" }
        return reminderDue ? "💀" : "🧠"
    }

    var menuBarTitle: String? {
        guard showTitleInMenuBar, reminderDue, !goalMet, !isSnoozed, let problem else { return nil }
        return "Remember? \(problem.title)"
    }

    var statusLine: String {
        switch state {
        case .idle: return "No agent running. Enjoy the silence."
        case .working(let agent, let since):
            let mins = max(Int(Date().timeIntervalSince(since) / 60), 0)
            return "\(agent.rawValue) has been working for \(mins) min."
        }
    }

    private func tick() {
        let now = Date()
        state = detector.ingest(source.snapshot())
        refreshToday(now: now) // also catches midnight rolling over
        var since: Date?
        if case .working(_, let s) = state { since = s }

        let streakWarning = streakInDanger
            ? Streak.warningInterval(at: now, warnFromHour: streakWarnFromHour) : nil
        if let reason = clock.evaluate(now: now, agentWorkingSince: since, goalMet: goalMet,
                                       streakWarning: streakWarning) {
            reminderDue = true
            nagReason = reason
            nag()
        }
        syncSnooze()
        if goalMet || isSnoozed || (nagReason == .agent && since == nil) {
            reminderDue = false
            nagReason = nil
        }
    }

    private func refreshToday(now: Date = Date()) {
        let counts = log.counts(on: now) { Self.difficultyBySlug[$0] }
        if counts != doneToday { doneToday = counts }
        let s = Streak(log: log, now: now)
        if s != streak { streak = s }
        let danger = streakWarnings && s.atRisk
            && Streak.warningInterval(at: now, warnFromHour: streakWarnFromHour) != nil
        if danger != streakInDanger { streakInDanger = danger }
    }

    /// e.g. "2h 14m" until midnight.
    var timeLeftToday: String {
        let minutes = Int(Streak.timeLeft(at: Date()) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func syncSnooze() {
        if snoozedUntil != clock.snoozedUntil { snoozedUntil = clock.snoozedUntil }
        snoozedUntilStored = snoozedUntil?.timeIntervalSince1970 ?? 0
    }

    enum SnoozeLength: CaseIterable, Identifiable {
        case fifteen, hour, today
        var id: Self { self }
        var label: String {
            switch self {
            case .fifteen: return "15 min"
            case .hour: return "1 hour"
            case .today: return "Rest of today"
            }
        }
    }

    func snooze(_ length: SnoozeLength) {
        let now = Date()
        let until: Date
        switch length {
        case .fifteen: until = now.addingTimeInterval(15 * 60)
        case .hour: until = now.addingTimeInterval(60 * 60)
        case .today: until = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        }
        clock.snooze(until: until)
        syncSnooze()
        reminderDue = false
        nagReason = nil
        reminderPanel.dismiss()
    }

    func resumeReminders() {
        clock.snooze(until: nil)
        syncSnooze()
    }

    private func nag() {
        switch reminderStyle {
        case .quiet: break
        case .popover: openPopover()
        case .center: reminderPanel.show(model: self)
        }
    }

    /// Shows the centered alert right now, so the user can see what it looks like.
    func previewReminder() { reminderPanel.show(model: self) }

    private func openPopover() {
        // The MenuBarExtra window is backed by the status item's button; simulate a click on it.
        for window in NSApp.windows {
            guard window.className.contains("NSStatusBarWindow"),
                  let button = window.contentView?.subviews.compactMap({ $0 as? NSStatusBarButton }).first
            else { continue }
            button.performClick(nil)
            return
        }
    }

    func solve() {
        if let problem { NSWorkspace.shared.open(problem.url) }
    }

    func markDone() {
        guard let problem else { return }
        done.insert(problem.slug)
        UserDefaults.standard.set(Array(done), forKey: "done")
        doneCount = done.count
        log.record(problem.slug, on: Date())
        UserDefaults.standard.set(log.days, forKey: "dailyLog")
        refreshToday()
        clock.noteActivity(at: Date())
        reminderDue = false
        nagReason = nil
        skipCount = 0
        advance()
    }

    func skip() {
        skipCount += 1
        if let problem, roadmap != nil { roadmapSkipped.insert(problem.slug) }
        advance()
    }

    func copyLink() {
        guard let problem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(problem.url.absoluteString, forType: .string)
    }

    func refreshTagline() { tagline = Taglines.random(excluding: tagline) }

    private func advance() {
        refreshTagline()
        pickNext()
    }

    private func pickNext() {
        if let roadmap {
            let step = roadmap.next(difficulties: focus, done: done, skipped: roadmapSkipped)
            problem = step?.problem
            domain = step?.domain
        } else {
            problem = picker.next(difficulties: focus, excluding: done)
            domain = nil
        }
    }

    /// The selected difficulties, narrowed to the ones today's goal still needs.
    private var focus: Set<Difficulty> { goal.focus(selected: difficulties, doneToday: doneToday) }

    private func filtersChanged() {
        // Keep the current problem if it still fits; otherwise pick a new one.
        if let problem, focus.contains(problem.difficulty), roadmap == nil { return }
        pickNext()
    }

    private func goalChanged() {
        objectWillChange.send()
        filtersChanged()
    }

    private func rulesChanged() { clock.rules = rules }

    private func roadmapChanged() {
        roadmap = Roadmap(mode: mode, order: order)
        roadmapSkipped = []
        pickNext()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("Launch at login failed: \(error)") }
        }
    }
}
