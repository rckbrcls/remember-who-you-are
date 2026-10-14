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
    @AppStorage("autoOpenPopover") var autoOpenPopover = false
    @AppStorage("includeEasy") var includeEasy = true
    @AppStorage("includeMedium") var includeMedium = true
    @AppStorage("includeHard") var includeHard = false

    private var detector = AgentDetector()
    private var picker = ProblemPicker()
    private var done: Set<String>
    private var timer: Timer?
    private let source: ProcessSource = PSProcessSource()
    private var notifiedForSession = false

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "done") ?? []
        done = Set(saved)
        doneCount = saved.count
        problem = picker.next(difficulties: difficulties, excluding: done)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
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
            if autoOpenPopover && !notifiedForSession {
                notifiedForSession = true
                openPopover()
            }
        }
    }

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
        advance()
    }

    func refreshTagline() { tagline = Taglines.random(excluding: tagline) }

    private func advance() {
        refreshTagline()
        problem = picker.next(difficulties: difficulties, excluding: done)
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
