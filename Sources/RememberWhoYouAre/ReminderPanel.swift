import SwiftUI
import AppKit
import RWYACore

/// How loudly the app nags when the reminder becomes due.
enum ReminderStyle: String, CaseIterable, Identifiable {
    case quiet, popover, center
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quiet: return "Just the menu bar icon"
        case .popover: return "Open the menu bar popover"
        case .center: return "Alert in the middle of the screen"
        }
    }
}

/// Borderless panel that can still take clicks and Escape without activating the app.
private final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// A floating, centered alert shown above everything (including full-screen apps).
@MainActor
final class ReminderPanel {
    private var panel: FloatingPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func show(model: AppModel) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI view draws its own; a window shadow outlines the clear margin
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.dismiss() }

        let controller = NSHostingController(rootView: ReminderAlertView(model: model) { [weak self] in self?.dismiss() })
        // Measure once and pin the window to that size, so it can't grow away from the center later.
        controller.sizingOptions = []
        let size = controller.sizeThatFits(in: NSSize(width: ReminderAlertView.windowWidth, height: 2000))
        panel.contentViewController = controller

        self.panel = panel
        center(panel, size: size)
        // Key (without activating the app) so the buttons render active and Esc/Return work.
        panel.makeKeyAndOrderFront(nil)
        NSSound(named: "Sosumi")?.play()
    }

    /// Centers on whichever screen the mouse is on — that's where the user is looking.
    private func center(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame, size.width > 0, size.height > 0 else { return }
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }
}

private struct ReminderAlertView: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void
    @State private var appeared = false
    static let margin: CGFloat = 40 // room for the shadow inside the clear window
    static let windowWidth: CGFloat = 420 + margin * 2

    var body: some View {
        VStack(spacing: 16) {
            Text("💀").font(.system(size: 56))
            Text(model.tagline)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)

            PracticeStack(model: model, afterAction: dismiss, large: true)
            Divider()

            StackSection("Snooze") {
                HStack(spacing: 6) {
                    ForEach(AppModel.SnoozeLength.allCases) { len in
                        Button(len.label) { model.snooze(len) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
            }

            Text("Esc to pretend you didn't see this")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .contentShape(.circle)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Close (Esc)")
            .padding(16)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .padding(Self.margin)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onExitCommand(perform: dismiss)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { appeared = true }
        }
    }
}
