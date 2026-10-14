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
            Divider()

            if let problem = model.problem {
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.title).font(.title3.bold())
                    Text("\(problem.difficulty.rawValue) · ~\(problem.minutes) min")
                        .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Easy", isOn: model.$includeEasy)
                Toggle("Medium", isOn: model.$includeMedium)
                Toggle("Hard", isOn: model.$includeHard)
            } header: { Label("Difficulty", systemImage: "gauge.with.dots.needle.67percent") }
            Section {
                Toggle("Show problem in menu bar", isOn: model.$showTitleInMenuBar)
                Toggle("Auto-open popover when the reminder is due", isOn: model.$autoOpenPopover)
            } header: { Label("Menu bar", systemImage: "menubar.rectangle") }
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
        .frame(width: 400, height: 520)
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
