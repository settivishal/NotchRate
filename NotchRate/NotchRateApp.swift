import SwiftUI

@main
struct NotchRateApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Pref.menuBarText) private var menuBarText = false
    @StateObject private var updates = UpdateCheck()
    @State private var connected = Statusline.isInstalled

    var body: some Scene {
        MenuBarExtra {
            Text(delegate.summary)
            Divider()
            if !connected { Button("Connect Claude Code status line…") { connect() } }
            if let u = updates.latest { Button("Update available: \(u.version)…") { NSWorkspace.shared.open(u.url) } }
            Button("Settings…") { NSApp.activate(); openSettings() }
            Button("Quit NotchRate") { NSApp.terminate(nil) }
        } label: {
            if menuBarText { Text(delegate.summary) } else { Image(systemName: "gauge.with.dots.needle.33percent") }
        }
        Settings { SettingsView() }
    }

    private func connect() {
        do { try Statusline.install(); connected = true } catch { NSAlert(error: error).runModal(); return }
        let a = NSAlert()
        a.messageText = "Status line connected"
        a.informativeText = "Restart Claude Code to start receiving cost and context data."
        a.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?  // NSApp.delegate is SwiftUI's wrapper, not this object
    private(set) var store: UsageStore!
    private var panel: NotchPanel!
    private(set) var state: NotchState!
    private var approvals: Approvals!
    private var tracker: ScreenTracker!
    private var poller: UsagePoller!
    private var collapseTask: Task<Void, Never>?
    private var previewing = false
    private var hotkeyOpened = false

    var summary: String {
        guard let s = store?.primary else { return "No usage data yet" }
        return "5h \(Int((s.sessionUsedPct ?? 0).rounded()))% · 7d \(Int((s.weeklyUsedPct ?? 0).rounded()))%"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Pref.register()
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()
        Statusline.refreshIfInstalled()

        store = UsageStore()
        store.onUpdate = { [weak self] old, new in
            Notifier.post(old: old, new: new)
            guard let self else { return }
            if let p = store.primary { History.append(p) }
            state?.tallCard = store.primary?.models?.isEmpty == false
            updateVisibility(screen: tracker?.current)
        }
        poller = UsagePoller(directory: store.directory)
        approvals = Approvals(directory: store.directory)
        approvals.onChange = { [weak self] in self?.approvalsChanged() }
        approvals.onPlanReady = {
            if UserDefaults.standard.bool(forKey: Pref.planNotify) { Notifier.post(title: "Claude", body: "Plan ready for review") }
        }

        state = NotchState(geometry: NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0]))
        state.onCaffeineChange = { [weak self] in
            guard let self, !state.expanded else { return }
            panel.setFrame(collapsedFrame, display: true)
        }
        panel = NotchPanel()
        panel.contentView = NSHostingView(rootView: NotchView(store: store, state: state,
                                                              setExpanded: { [weak self] in self?.setExpanded($0) },
                                                              setPage: { [weak self] in self?.setPage($0) },
                                                              refresh: { [weak self] in self?.refresh() },
                                                              togglePin: { [weak self] in self?.togglePin() },
                                                              answer: { [weak self] in self?.approvals.answer($0, $1) }))
        panel.onSwipe = { [weak self] in self?.swipe($0) }
        HotKey.set(enabled: UserDefaults.standard.bool(forKey: Pref.hotkey)) { [weak self] in self?.toggleFromHotkey() }

        tracker = ScreenTracker(followMouse: UserDefaults.standard.bool(forKey: Pref.allDisplays)) { [weak self] in self?.move(to: $0) }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.setFollowMouse(UserDefaults.standard.bool(forKey: Pref.allDisplays))
                HotKey.set(enabled: UserDefaults.standard.bool(forKey: Pref.hotkey)) { [weak self] in self?.toggleFromHotkey() }
                if !self.previewing { self.move(to: self.tracker.current) }  // wing width may have changed
            }
        }
    }

    private func move(to screen: NSScreen?) {
        guard let screen else { panel.orderOut(nil); return }
        state.geometry = NotchGeometry(screen: screen)
        state.expanded = false
        panel.setFrame(collapsedFrame, display: true)
        updateVisibility(screen: screen)
    }

    private var collapsedFrame: NSRect { state.geometry.frame(for: state.geometry.collapsedSize(island: state.approval != nil, blob: state.caffeinated)) }

    private func updateVisibility(screen: NSScreen?) {
        let empty = store.primary == nil && state.approval == nil
        if empty || screen == nil || UserDefaults.standard.bool(forKey: Pref.hideBadge) { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Pending permission request → island (collapsed) or banner (expanded); notify once per new request.
    private func approvalsChanged() {
        let defaults = UserDefaults.standard
        let new = approvals.current.flatMap { defaults.bool(forKey: $0.isPlan ? Pref.planNotify : Pref.approvals) ? $0 : nil }
        guard new != state.approval else { return }
        if let new, !new.isPlan, new.id != state.approval?.id { Notifier.post(title: "Claude", body: "\(new.tool) needs permission") }
        state.approval = new
        if state.expanded {
            if new != nil { setPage(.approval) } else if state.page == .approval { setPage(.overview) }
        } else {
            panel.setFrame(collapsedFrame, display: true)
        }
        updateVisibility(screen: tracker.current)
    }

    private func swipe(_ dir: Int) {
        let tabs = Tab.allCases
        guard state.expanded, let i = tabs.firstIndex(of: state.page.tab) else { return }
        let n = min(max(i + dir, 0), tabs.count - 1)
        if n != i { setPage(tabs[n].pages[0]) }
    }

    private func expandedSize(for page: Page) -> CGSize {
        state.geometry.expandedSize(for: page, tall: state.tallCard, plan: state.approval?.isPlan == true)
    }

    /// Window grows before the expand animation and shrinks after the collapse one,
    /// so the transparent hit area never blocks clicks while collapsed.
    private func setExpanded(_ on: Bool) {
        if (previewing || state.pinned) && !on { return }  // slider preview or pin holds the card open
        collapseTask?.cancel()
        guard on != state.expanded else { return }
        if on {
            if state.approval != nil { state.page = .approval }  // pending request opens on its own page
            panel.setFrame(state.geometry.frame(for: expandedSize(for: state.page)), display: true)
            state.expanded = true
        } else {
            state.expanded = false
            state.page = .overview
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(300))  // just past the collapse spring
                guard !Task.isCancelled, !state.expanded else { return }
                panel.setFrame(collapsedFrame, display: true)
            }
        }
    }

    /// Settings sliders call this while dragging so the user sees the card change live.
    func preview(_ on: Bool) {
        previewing = on
        if on { updateVisibility(screen: tracker.current) }
        setExpanded(on)
    }

    func togglePin() {
        state.pinned.toggle()
        if !state.pinned { setExpanded(false) }
    }

    /// Hotkey opens the card pinned on the screen under the mouse; pressing again closes it.
    private func toggleFromHotkey() {
        if state.expanded { state.pinned = false; setExpanded(false); return }
        move(to: tracker.current)
        state.pinned = true
        setExpanded(true)
    }

    private func refresh() {
        guard !state.refreshing else { return }
        state.refreshing = true
        Task { await poller.poll(); state.refreshing = false }
    }

    /// Window takes the larger of old/new page sizes during the switch, then settles.
    private func setPage(_ page: Page) {
        let old = panel.frame.size, new = expandedSize(for: page)
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
