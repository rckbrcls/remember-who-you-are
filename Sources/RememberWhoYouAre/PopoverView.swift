import SwiftUI
import RWYACore
import Sparkle

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.tagline)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            PracticeStack(model: model)
            Divider()
            VStack(spacing: 0) {
                SnoozeRow(model: model)
                MenuRow(symbol: "arrow.triangle.2.circlepath", title: "Check for Updates…", enabled: updates.canCheck) {
                    updates.check()
                }
                MenuRow(symbol: "gearshape", title: "Settings…", shortcut: "⌘,") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuRow(symbol: "info.circle", title: "About Remember Who You Are") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                MenuRow(symbol: "xmark.square", title: "Quit", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, -6)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refreshTagline() }
        .containerBackground(.clear, for: .window)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @AppStorage("settingsTab") private var tab = "problems"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Problems", systemImage: "list.bullet.rectangle", value: "problems") { problems }
            Tab("Goals", systemImage: "target", value: "goals") { goals }
            Tab("Reminders", systemImage: "bell.badge", value: "reminders") { reminders }
            Tab("History", systemImage: "calendar", value: "history") { HistoryView(model: model) }
            Tab("General", systemImage: "gearshape", value: "general") { general }
        }
        .frame(width: 620, height: 540)
    }

    private var problems: some View {
        Form {
            Section {
                Picker("Problems", selection: model.binding(\.modeRaw)) {
                    ForEach(PracticeMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if model.mode != .random {
                    Picker("Progression", selection: model.binding(\.orderRaw)) {
                        ForEach(RoadmapOrder.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    if let progress = model.roadmapProgress {
                        LabeledContent("Progress", value: progress)
                    }
                }
            } header: { Label("Roadmap", systemImage: "map") } footer: {
                if model.mode != .random {
                    Text("Domain by domain follows NeetCode's order (Arrays & Hashing → … → Bit Manipulation), easy to hard inside each domain. Premium-only problems are left out.")
                }
            }
            Section {
                Toggle("Easy", isOn: model.binding(\.includeEasy)).disabled(model.difficulties == [.easy])
                Toggle("Medium", isOn: model.binding(\.includeMedium)).disabled(model.difficulties == [.medium])
                Toggle("Hard", isOn: model.binding(\.includeHard)).disabled(model.difficulties == [.hard])
            } header: { Label("Difficulty", systemImage: "gauge.with.dots.needle.67percent") }
        }
        .formStyle(.grouped)
    }

    private var goals: some View {
        Form {
            Section {
                goalStepper(.easy, \.goalEasy)
                goalStepper(.medium, \.goalMedium)
                goalStepper(.hard, \.goalHard)
            } header: { Label("Daily goal", systemImage: "target") } footer: {
                Text(model.goal.isActive
                     ? "Problems come from the difficulties you still owe today. Once the goal is met, reminders stop until tomorrow."
                     : "Set at least one target to turn on the daily goal.")
            }
            if model.goal.isActive {
                Section("Today") { GoalRow(model: model) }
            }
            Section {
                LabeledContent("Current", value: "\(model.streak.current) day\(model.streak.current == 1 ? "" : "s")")
                LabeledContent("Best", value: "\(model.streak.best) day\(model.streak.best == 1 ? "" : "s")")
                Toggle("Warn me before the day ends", isOn: model.$streakWarnings)
                if model.streakWarnings {
                    Stepper(value: model.$streakWarnFromHour, in: 17...23) {
                        Text("Starting at \(model.streakWarnFromHour):00")
                    }
                }
            } header: { Label("Streak", systemImage: "flame") } footer: {
                Text("Solve at least one problem a day to keep the streak. If nothing is solved yet, reminders come hourly from the start time, every 30 min after 22:00 and every 15 min after 23:00. Snoozing still silences them.")
            }
        }
        .formStyle(.grouped)
    }

    private func goalStepper(_ d: Difficulty, _ kp: ReferenceWritableKeyPath<AppModel, Int>) -> some View {
        Stepper(value: model.binding(kp), in: 0...10) {
            HStack {
                Circle().fill(d.tint).frame(width: 8, height: 8)
                Text(d.rawValue)
                Spacer()
                Text(model[keyPath: kp] == 0 ? "Off" : "\(model[keyPath: kp]) / day").foregroundStyle(.secondary)
            }
        }
    }

    private var reminders: some View {
        Form {
            Section {
                Toggle("When an AI agent is working", isOn: model.binding(\.remindOnAgent))
                if model.remindOnAgent {
                    Stepper(value: model.binding(\.delayMinutes), in: 0...30) {
                        Text(model.delayMinutes == 0 ? "As soon as it starts" : "After \(model.delayMinutes) min of work")
                    }
                }
                Toggle("Every so often", isOn: model.binding(\.remindOnInterval))
                if model.remindOnInterval {
                    Stepper(value: model.binding(\.intervalMinutes), in: 15...240, step: 15) {
                        Text("Every \(intervalLabel(model.intervalMinutes))")
                    }
                }
            } header: { Label("Remind me", systemImage: "bell") } footer: {
                Text("Solving a problem restarts the timer. Nothing fires while snoozed or after today's goal is met.")
            }
            Section {
                Picker("Style", selection: model.$reminderStyleRaw) {
                    ForEach(ReminderStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Button("Preview alert") { model.previewReminder() }
            } header: { Label("How", systemImage: "exclamationmark.bubble") }
            Section {
                if let until = model.snoozedUntil, model.isSnoozed {
                    LabeledContent("Snoozed until", value: until.formatted(date: .omitted, time: .shortened))
                    Button("Resume now") { model.resumeReminders() }
                } else {
                    HStack {
                        ForEach(AppModel.SnoozeLength.allCases) { len in
                            Button(len.label) { model.snooze(len) }
                        }
                    }
                }
            } header: { Label("Snooze", systemImage: "moon.zzz") }
        }
        .formStyle(.grouped)
    }

    private func intervalLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : minutes > 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Toggle("Show problem in menu bar", isOn: model.$showTitleInMenuBar)
            } header: { Label("General", systemImage: "gearshape") }
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 }))
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck)
            } header: { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .formStyle(.grouped)
    }
}

/// The shared body of the popover and the reminder alert, top to bottom:
/// streak warning, stats, daily goal, the problem with its actions, then where problems come from.
struct PracticeStack: View {
    @ObservedObject var model: AppModel
    /// Runs after Solve / Done / Skip (the alert closes itself here).
    var afterAction: () -> Void = {}
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StreakBanner(model: model)

            StackSection("Progress") {
                HStack(spacing: 8) {
                    StatCard(emoji: "✅", value: model.doneCount, label: "Solved", dimmed: model.doneCount == 0)
                    StreakCard(model: model)
                }
                GoalRow(model: model)
            }
            Divider()

            StackSection("Up next") {
            if let problem = model.problem {
                ProblemCard(model: model, problem: problem, large: large)
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        Button("Solve on LeetCode") { model.solve(); afterAction() }
                            .buttonStyle(CardButtonStyle(prominent: true))
                            .keyboardShortcut(.defaultAction)
                        HStack(spacing: 8) {
                            Button("Done") { model.markDone(); afterAction() }
                            Button("Skip 💀") { model.skip(); afterAction() }
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            } else if model.roadmapProgress != nil {
                Text("\(model.mode.title) done for these difficulties. Who even are you? 🏆").font(.subheadline)
            } else {
                Text("You solved everything in this difficulty. Suspicious. 🤨").font(.subheadline)
            }
            }
            Divider()

            StackSection("Practice") {
                HStack(spacing: 8) {
                    Picker("Mode", selection: model.binding(\.modeRaw)) {
                        ForEach(PracticeMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Spacer(minLength: 0)
                    DifficultyChips(model: model)
                }
            }
        }
    }
}

/// One corner radius for every card and card-sized button.
enum CardStyle {
    static let radius: CGFloat = 16
}

/// A glass button shaped exactly like the cards (the system glass styles pick their own corners).
struct CardButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(.rect(cornerRadius: CardStyle.radius))
            .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: CardStyle.radius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small uppercase heading over a group of rows.
struct StackSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Problems solved per day, newest first, each linking to LeetCode.
struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let days = model.history
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatCard(emoji: "📅", value: days.count, label: "Days practiced", dimmed: days.isEmpty)
                StatCard(emoji: "✅", value: days.reduce(0) { $0 + $1.problems.count }, label: "Problems", dimmed: days.isEmpty)
                StreakCard(model: model)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, days.isEmpty ? 0 : 4)

            if days.isEmpty {
                ContentUnavailableView("Nothing solved yet",
                                       systemImage: "calendar.badge.clock",
                                       description: Text("Problems you mark as Done show up here, grouped by day."))
                    .frame(maxHeight: .infinity)
            } else {
                Form {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.problems) { problem in
                                HistoryRow(problem: problem)
                            }
                        } header: {
                            HStack {
                                Text(dayTitle(day.day))
                                Spacer()
                                Text("\(day.problems.count) solved").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
    }
}

private struct HistoryRow: View {
    let problem: Problem
    @State private var hovering = false

    var body: some View {
        Link(destination: problem.url) {
            HStack(spacing: 8) {
                DifficultyBadge(difficulty: problem.difficulty)
                Text(problem.title).foregroundStyle(.primary)
                Spacer()
                Text("~\(problem.minutes) min").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovering ? .primary : .tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(problem.url.absoluteString)
        .contextMenu {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(problem.url.absoluteString, forType: .string)
            }
        }
    }
}

/// The current problem: domain (in a roadmap), title, a colored difficulty badge, and copy-link.
struct ProblemCard: View {
    @ObservedObject var model: AppModel
    let problem: Problem
    var large = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                if let domain = model.domainProgress {
                    Text(domain.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                Text(problem.title)
                    .font(large ? .title2.bold() : .title3.bold())
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    DifficultyBadge(difficulty: problem.difficulty)
                    Text("~\(problem.minutes) min").font(.caption).foregroundStyle(.secondary)
                    if let overall = model.roadmapProgress {
                        Text("· \(overall)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CopyLinkButton(model: model)
        }
        .padding(large ? 14 : 12)
        .glassEffect(.regular, in: .rect(cornerRadius: CardStyle.radius))
    }
}

struct DifficultyBadge: View {
    let difficulty: Difficulty
    var body: some View {
        Text(difficulty.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(difficulty.tint)
            .background(difficulty.tint.opacity(0.18), in: .capsule)
    }
}

/// Emoji and a big number side by side, with a label underneath.
struct StatCard: View {
    let emoji: String
    let value: Int
    let label: String
    var dimmed = false
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(emoji).font(.title2)
                    .saturation(dimmed ? 0 : 1).opacity(dimmed ? 0.6 : 1)
                Text("\(value)").font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            }
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: CardStyle.radius))
        .help(help ?? "")
    }
}

/// The streak card; the flame is grey while today's problem is still owed.
struct StreakCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let s = model.streak
        StatCard(emoji: "🔥", value: s.current, label: "Day streak",
                 dimmed: !s.doneToday,
                 help: s.doneToday ? "Today is done. Best: \(s.best) days."
                     : s.current > 0 ? "Solve one today to keep it. Best: \(s.best) days."
                     : "Solve one today to start a streak.")
    }
}

/// Warning shown while the streak is about to end.
struct StreakBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.streakInDanger {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 10) {
                    Text("🔥").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        (Text("Your \(model.streak.current)-day streak ends in ")
                         + Text(model.timeLeftToday).foregroundStyle(.red))
                            .font(.callout.weight(.bold))
                        Text("Solve one problem to keep it alive.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: CardStyle.radius))
            }
        }
    }
}

/// Today's progress toward the daily goal, e.g. "Easy 1/2 · Medium 0/1".
struct GoalRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.goalMet {
            Label("Daily goal done. Reminders off until tomorrow.", systemImage: "trophy.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.goalItems.isEmpty {
            HStack(spacing: 6) {
                Label("Daily goal", systemImage: "target")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ForEach(model.goalItems, id: \.difficulty) { item in
                    let complete = item.done >= item.target
                    HStack(spacing: 3) {
                        if complete { Image(systemName: "checkmark").font(.caption2.bold()) }
                        Text("\(item.difficulty.short) \(item.done)/\(item.target)")
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .foregroundStyle(complete ? Color.white : item.difficulty.tint)
                    .background(complete ? item.difficulty.tint : item.difficulty.tint.opacity(0.18), in: .capsule)
                }
            }
        }
    }
}

/// "Snooze reminders ▸" in the popover's menu list, or "Snoozed until … · Resume".
struct SnoozeRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let until = model.snoozedUntil, model.isSnoozed {
            MenuRow(symbol: "moon.zzz.fill",
                    title: "Snoozed until \(until.formatted(date: .omitted, time: .shortened))",
                    shortcut: "Resume") { model.resumeReminders() }
        } else {
            Menu {
                ForEach(AppModel.SnoozeLength.allCases) { len in
                    Button(len.label) { model.snooze(len) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz").frame(width: 18)
                    Text("Snooze reminders")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .font(.callout)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }
}

/// Multi-select Easy / Medium / Hard; at least one always stays on.
struct DifficultyChips: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Difficulty.allCases, id: \.self) { d in
                let on = model.isIncluded(d)
                Button { model.toggle(d) } label: {
                    Text(d.short)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .background(on ? d.tint : Color.primary.opacity(0.08), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(on ? "Stop recommending \(d.rawValue) problems" : "Recommend \(d.rawValue) problems")
            }
        }
        .animation(.snappy(duration: 0.15), value: model.difficulties)
    }
}

extension Difficulty {
    var short: String { self == .medium ? "Med" : rawValue }
    var tint: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

/// Copies the problem URL and flashes a checkmark.
struct CopyLinkButton: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        Button {
            model.copyLink()
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "link")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Copy problem link")
    }
}

struct MenuRow: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.tertiary) }
            }
            .font(.callout)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(.rect)
            .background(hovering && enabled ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var canCheck = false
    private let updater: SPUUpdater
    private let action: () -> Void
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater, action: @escaping () -> Void) {
        self.updater = updater
        self.action = action
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    var automaticChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }

    func check() { action() }
}
