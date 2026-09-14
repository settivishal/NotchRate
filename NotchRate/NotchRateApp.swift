import SwiftUI

@main
struct NotchRateApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("NotchRate", systemImage: "gauge.with.dots.needle.33percent") {
            Text(delegate.summary)
            Divider()
            Button("Settings…") { NSApp.activate(); openSettings() }
            Button("Quit NotchRate") { NSApp.terminate(nil) }
        }
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store: UsageStore!
    private var panel: NotchPanel!
    private var state: NotchState!
    private var tracker: ScreenTracker!
    private var collapseTask: Task<Void, Never>?

    var summary: String {
        guard let s = store?.primary else { return "No usage data yet" }
        return "Session \(Int((s.sessionUsedPct ?? 0).rounded()))% · Weekly \(Int((s.weeklyUsedPct ?? 0).rounded()))%"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()

        store = UsageStore()
        store.onUpdate = { [weak self] old, new in
            Notifier.post(old: old, new: new)
            guard let self else { return }
            updateVisibility(screen: tracker?.current)
        }

        state = NotchState(geometry: NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0]))
        panel = NotchPanel()
        panel.contentView = NSHostingView(rootView: NotchView(store: store, state: state) { [weak self] in self?.setExpanded($0) })

        tracker = ScreenTracker(followMouse: UserDefaults.standard.bool(forKey: Pref.allDisplays)) { [weak self] in self?.move(to: $0) }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.setFollowMouse(UserDefaults.standard.bool(forKey: Pref.allDisplays))
                self.move(to: self.tracker.current)  // wing width may have changed
            }
        }
    }

    private func move(to screen: NSScreen?) {
        guard let screen else { panel.orderOut(nil); return }
        state.geometry = NotchGeometry(screen: screen)
        state.expanded = false
        panel.setFrame(state.geometry.frame(for: state.geometry.collapsedSize), display: true)
        updateVisibility(screen: screen)
    }

    private func updateVisibility(screen: NSScreen?) {
        if store.primary == nil || screen == nil { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Window grows before the expand animation and shrinks after the collapse one,
    /// so the transparent hit area never blocks clicks while collapsed.
    private func setExpanded(_ on: Bool) {
        collapseTask?.cancel()
        guard on != state.expanded else { return }
        if on {
            panel.setFrame(state.geometry.frame(for: state.geometry.expandedSize), display: true)
            state.expanded = true
        } else {
            state.expanded = false
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, !state.expanded else { return }
                panel.setFrame(state.geometry.frame(for: state.geometry.collapsedSize), display: true)
            }
        }
    }
}
