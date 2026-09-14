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
    static var shared: AppDelegate?  // NSApp.delegate is SwiftUI's wrapper, not this object
    private(set) var store: UsageStore!
    private var panel: NotchPanel!
    private var state: NotchState!
    private var tracker: ScreenTracker!
    private var poller: UsagePoller!
    private var collapseTask: Task<Void, Never>?
    private var previewing = false

    var summary: String {
        guard let s = store?.primary else { return "No usage data yet" }
        return "5h \(Int((s.sessionUsedPct ?? 0).rounded()))% · 7d \(Int((s.weeklyUsedPct ?? 0).rounded()))%"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Pref.register()
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()

        store = UsageStore()
        store.onUpdate = { [weak self] old, new in
            Notifier.post(old: old, new: new)
            guard let self else { return }
            if let p = store.primary { History.append(p) }
            updateVisibility(screen: tracker?.current)
        }
        poller = UsagePoller(directory: store.directory)

        state = NotchState(geometry: NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0]))
        panel = NotchPanel()
        panel.contentView = NSHostingView(rootView: NotchView(store: store, state: state,
                                                              setExpanded: { [weak self] in self?.setExpanded($0) },
                                                              setPage: { [weak self] in self?.setPage($0) },
                                                              refresh: { [weak self] in self?.refresh() }))

        tracker = ScreenTracker(followMouse: UserDefaults.standard.bool(forKey: Pref.allDisplays)) { [weak self] in self?.move(to: $0) }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.setFollowMouse(UserDefaults.standard.bool(forKey: Pref.allDisplays))
                if !self.previewing { self.move(to: self.tracker.current) }  // wing width may have changed
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
        if store.primary == nil || screen == nil || UserDefaults.standard.bool(forKey: Pref.hideBadge) { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Window grows before the expand animation and shrinks after the collapse one,
    /// so the transparent hit area never blocks clicks while collapsed.
    private func setExpanded(_ on: Bool) {
        if previewing && !on { return }  // settings slider is showing the card; ignore hover-out
        collapseTask?.cancel()
        guard on != state.expanded else { return }
        if on {
            panel.setFrame(state.geometry.frame(for: state.geometry.expandedSize(for: state.page)), display: true)
            state.expanded = true
        } else {
            state.expanded = false
            state.page = .overview
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, !state.expanded else { return }
                panel.setFrame(state.geometry.frame(for: state.geometry.collapsedSize), display: true)
            }
        }
    }

    /// Settings sliders call this while dragging so the user sees the card change live.
    func preview(_ on: Bool) {
        previewing = on
        if on { updateVisibility(screen: tracker.current) }
        setExpanded(on)
    }

    private func refresh() {
        guard !state.refreshing else { return }
        state.refreshing = true
        Task { await poller.poll(); state.refreshing = false }
    }

    /// Window takes the larger of old/new page sizes during the switch, then settles.
    private func setPage(_ page: Page) {
        let old = state.geometry.expandedSize(for: state.page), new = state.geometry.expandedSize(for: page)
        panel.setFrame(state.geometry.frame(for: CGSize(width: max(old.width, new.width), height: max(old.height, new.height))), display: true)
        state.page = page
        if new != old {
            collapseTask?.cancel()
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, state.expanded, state.page == page else { return }
                panel.setFrame(state.geometry.frame(for: new), display: true)
            }
        }
    }
}
