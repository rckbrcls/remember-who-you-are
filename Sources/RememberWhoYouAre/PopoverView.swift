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

            HStack {
                Label("Solved", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(model.doneCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))

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
            Divider()

            if let problem = model.problem {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem.title).font(.title3.bold())
                        Text("\(problem.difficulty.rawValue) · ~\(problem.minutes) min")
                            .font(.caption).foregroundStyle(.secondary)
                        if let domain = model.domainProgress, let overall = model.roadmapProgress {
                            Text("\(domain) · \(overall)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    CopyLinkButton(model: model)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        Button { model.solve() } label: {
                            Text("Solve on LeetCode").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        HStack(spacing: 8) {
                            Button { model.markDone() } label: {
                                Text("Done").frame(maxWidth: .infinity, minHeight: 40)
                            }
                            Button { model.skip() } label: {
                                Text(model.skipLabel)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
            } else if model.roadmapProgress != nil {
                Text("\(model.mode.title) done for these difficulties. Who even are you? 🏆").font(.subheadline)
            } else {
                Text("You solved everything in this difficulty. Suspicious. 🤨").font(.subheadline)
            }

            Divider()
            VStack(spacing: 0) {
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

    var body: some View {
        Form {
            Section {
                Stepper("Remind after \(model.delayMinutes) min of agent work", value: model.$delayMinutes, in: 1...30)
            } header: { Label("Reminder", systemImage: "bell") }
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
                    Text("Premium-only problems are left out. Done problems count toward every roadmap.")
                }
            }
            Section {
                Toggle("Easy", isOn: model.binding(\.includeEasy)).disabled(model.difficulties == [.easy])
                Toggle("Medium", isOn: model.binding(\.includeMedium)).disabled(model.difficulties == [.medium])
                Toggle("Hard", isOn: model.binding(\.includeHard)).disabled(model.difficulties == [.hard])
            } header: { Label("Difficulty", systemImage: "gauge.with.dots.needle.67percent") }
            Section {
                Toggle("Show problem in menu bar", isOn: model.$showTitleInMenuBar)
            } header: { Label("Menu bar", systemImage: "menubar.rectangle") }
            Section {
                Picker("When the reminder is due", selection: model.$reminderStyleRaw) {
                    ForEach(ReminderStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Button("Preview alert") { model.previewReminder() }
            } header: { Label("Nagging", systemImage: "exclamationmark.bubble") }
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 }))
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck)
            } header: { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            } header: { Label("General", systemImage: "gearshape") }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 720)
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

private struct MenuRow: View {
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
