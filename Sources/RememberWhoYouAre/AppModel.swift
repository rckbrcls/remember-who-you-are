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

    @AppStorage("delayMinutes") var delayMinutes = 2
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
    private var notifiedForSession = false
    private let reminderPanel = ReminderPanel()

    var reminderStyle: ReminderStyle { ReminderStyle(rawValue: reminderStyleRaw) ?? .center }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "done") ?? []
        done = Set(saved)
        doneCount = saved.count
        roadmap = Roadmap(mode: mode, order: order)
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

    var skipLabel: String { SkipPhrases.phrase(forSkipCount: skipCount) }

    var menuBarEmoji: String { reminderDue ? "💀" : "🧠" }

    var menuBarTitle: String? {
        guard showTitleInMenuBar, reminderDue, let problem else { return nil }
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
        let samples = source.snapshot()
        let previous = state
        state = detector.ingest(samples)
        guard case .working(_, let since) = state else {
            reminderDue = false
            notifiedForSession = false
            return
        }
        if case .idle = previous { notifiedForSession = false }
        let elapsed = Date().timeIntervalSince(since)
        if elapsed >= Double(delayMinutes) * 60 {
            reminderDue = true
            if !notifiedForSession {
                notifiedForSession = true
                nag()
            }
        }
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
            let step = roadmap.next(difficulties: difficulties, done: done, skipped: roadmapSkipped)
            problem = step?.problem
            domain = step?.domain
        } else {
            problem = picker.next(difficulties: difficulties, excluding: done)
            domain = nil
        }
    }

    private func filtersChanged() {
        // Keep the current problem if it still fits; otherwise pick a new one.
        if let problem, difficulties.contains(problem.difficulty), roadmap == nil { return }
        pickNext()
    }

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
