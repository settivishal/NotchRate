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
            if menuBarText { Text(delegate.summary) } else { Image(nsImage: Brand.glyph).resizable().frame(width: 13, height: 13) }
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

enum Brand {
    /// Template glyph: bold N with the notch bitten out of its top, dot inside the bite. Drawn as vectors on an
    /// 18pt grid with whole-point edges, so it re-renders crisp at every menu bar scale.
    static let glyph: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let n = CGMutablePath()
            n.addLines(between: [CGPoint(x: 2, y: 1), CGPoint(x: 6, y: 1), CGPoint(x: 12, y: 10), CGPoint(x: 12, y: 1), CGPoint(x: 16, y: 1),
                                 CGPoint(x: 16, y: 17), CGPoint(x: 12, y: 17), CGPoint(x: 6, y: 8), CGPoint(x: 6, y: 17), CGPoint(x: 2, y: 17)])
            n.closeSubpath()
            cg.setFillColor(.black)
            cg.addPath(n); cg.fillPath()
            cg.setBlendMode(.destinationOut)
            cg.addPath(CGPath(roundedRect: CGRect(x: 5, y: -2, width: 8, height: 8.5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); cg.fillPath()
            cg.setBlendMode(.normal)
            cg.fillEllipse(in: CGRect(x: 6.5, y: 2, width: 2.5, height: 2.5))
            return true
        }
        img.isTemplate = true
        return img
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?  // NSApp.delegate is SwiftUI's wrapper, not this object
    private(set) var store: UsageStore!
    private var panel: NotchPanel!
    private var canvas: NotchCanvas!
    private(set) var state: NotchState!
    private var approvals: Approvals!
    private var tracker: ScreenTracker!
    private var poller: UsagePoller!
    private var transition = 0  // latest island transition; a stale spring completion is ignored
    private var animating = false
    private var blobChange = 0  // same, for blob pop-in completions
    private var hoverTask: Task<Void, Never>?
    private var pointerInside = false
    private var hoverSuppressed = false  // closed by click/hotkey with the pointer on it: no reopen until it leaves
    private var previewing = false
    private var hotkeyOpened = false
    static let terminals: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",  // last one is Cursor
    ]

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
            let hit = store.primary.map { ($0.sessionUsedPct ?? 0) >= 100 || ($0.weeklyUsedPct ?? 0) >= 100 } ?? false
            if let state, hit != state.limitHit { state.limitHit = hit; syncBlobs() }
            updateVisibility(screen: tracker?.current)
        }
        poller = UsagePoller(directory: store.directory)
        approvals = Approvals(directory: store.directory)
        approvals.onChange = { [weak self] in self?.approvalsChanged() }
        approvals.onPlanReady = {
            if UserDefaults.standard.bool(forKey: Pref.planNotify) { Notifier.post(title: "Claude", body: "Plan ready for review") }
        }

        state = NotchState(geometry: NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0]))
        state.onBlobChange = { [weak self] in self?.syncBlobs() }
        panel = NotchPanel()
        let view = { [unowned self] (part: NotchView.Part) in
            FirstClickHostingView(rootView: NotchView(part: part, store: store, state: state,
                                              setExpanded: { [weak self] in self?.setExpanded($0) },
                                              setPage: { [weak self] in self?.setPage($0) },
                                              refresh: { [weak self] in self?.refresh() },
                                              togglePin: { [weak self] in self?.togglePin() },
                                              answer: { [weak self] in self?.approvals.answer($0, $1) },
                                              clearDone: { [weak self] in self?.approvals.clearDone() }))
        }
        canvas = NotchCanvas(badge: view(.badge), card: view(.card))
        canvas.onPointer = { [weak self] in self?.hover() }
        panel.contentView = canvas
        // The "done" blob persists until the user looks at a terminal.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier, Self.terminals.contains(id) else { return }
            Task { @MainActor in self?.approvals.clearDone() }
        }
        panel.onSwipe = { [weak self] in self?.swipe($0) }
        HotKey.set(enabled: UserDefaults.standard.bool(forKey: Pref.hotkey)) { [weak self] in self?.toggleFromHotkey() }

        tracker = ScreenTracker(followMouse: UserDefaults.standard.bool(forKey: Pref.allDisplays)) { [weak self] in self?.move(to: $0) }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.setFollowMouse(UserDefaults.standard.bool(forKey: Pref.allDisplays))
                HotKey.set(enabled: UserDefaults.standard.bool(forKey: Pref.hotkey)) { [weak self] in self?.toggleFromHotkey() }
                // Any defaults write lands here (AppKit's text system writes some on first layout), so only
                // re-place the island when its size really changed; moving collapses an open card.
                if self.previewing { self.present(animated: false) }  // sliders reshape the open card live
                else if let screen = self.tracker.current, NotchGeometry(screen: screen).collapsedSize != self.state.geometry.collapsedSize {
                    self.move(to: screen)
                } else { self.updateVisibility(screen: self.tracker.current) }
            }
        }
    }

    private func move(to screen: NSScreen?) {
        guard let screen else { panel.orderOut(nil); return }
        state.geometry = NotchGeometry(screen: screen)
        canvas.notch = state.geometry.hasNotch
        state.expanded = false
        present(animated: false)
        updateVisibility(screen: screen)
    }

    private var silhouetteSize: CGSize { state.expanded ? expandedSize(for: state.page) : state.geometry.collapsedSize }
    private var windowSize: CGSize { state.expanded ? expandedSize(for: state.page) : state.geometry.collapsedSize(blob: state.slack) }

    /// Springs the silhouette to the current state. The window takes the union of old and new sizes first and
    /// settles to the new one when the spring ends, so neither end is clipped and nothing waits on a guessed delay.
    private func present(animated: Bool = true, delay: TimeInterval = 0, fade: NotchCanvas.Fade = .none) {
        transition += 1
        let id = transition, target = windowSize, old = panel.frame.size
        let envelope = animated ? CGSize(width: max(old.width, target.width), height: max(old.height, target.height)) : target
        animating = animated && !Motion.reduce
        canvas.transition(to: silhouetteSize, animated: animating, delay: delay, fade: fade) {
            panel.setFrame(state.geometry.frame(for: envelope), display: false)
        } done: { [weak self] in
            guard let self, id == transition else { return }
            settle()
        }
    }

    private func settle() {
        animating = false
        if !state.expanded {
            state.cardShown = false
            canvas.cardVisible = false
            state.page = .overview
        }
        canvas.badgeSize = state.geometry.collapsedSize(blob: state.slack)
        panel.setFrame(state.geometry.frame(for: windowSize), display: true)
        hover()
    }

    /// Blob came or went: grow the collapsed window before one pops out, shrink it once the last is back in.
    private func syncBlobs() {
        let timer = state.timerActive, claude = state.claudeActive
        guard timer != state.timerBlob || claude != state.claudeBlob else { return }
        blobChange += 1
        let id = blobChange
        if (timer || claude) && !state.slack { state.slack = true; fitCollapsed() }
        withAnimation(Motion.goo(), completionCriteria: .removed) {
            state.timerBlob = timer
            state.claudeBlob = claude
        } completion: { [weak self] in
            guard let self, id == blobChange, !state.timerBlob, !state.claudeBlob else { return }
            state.slack = false
            fitCollapsed()
        }
    }

    /// Collapsed and at rest: window follows the blob room at once (the silhouette does not change).
    private func fitCollapsed() {
        guard !state.expanded, !animating else { return }  // settle() applies it otherwise
        canvas.badgeSize = state.geometry.collapsedSize(blob: state.slack)
        panel.setFrame(state.geometry.frame(for: windowSize), display: true)
    }

    /// Hover area of where the island is heading, not of the moving silhouette: a resize never turns a still
    /// pointer into an exit. Collapsed, it skips the empty strip mirroring a lone side blob.
    private var hoverRect: NSRect {
        let frame = state.geometry.frame(for: windowSize)
        guard !state.expanded, state.slack, state.timerBlob != state.claudeBlob else { return frame }
        let inset = state.geometry.blobWidth + NotchGeometry.blobGap
        let blobLeft = UserDefaults.standard.bool(forKey: Pref.blobLeft)
        let mirrorOnLeft = state.timerBlob ? !blobLeft : blobLeft
        return NSRect(x: frame.minX + (mirrorOnLeft ? inset : 0), y: frame.minY, width: frame.width - inset, height: frame.height)
    }

    /// Acts only when the pointer crosses the hover area. Opening and closing both wait and re-check the
    /// pointer, so brushing past the notch or a momentary exit does nothing.
    private func hover() {
        let inside = hoverRect.contains(NSEvent.mouseLocation)
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverTask?.cancel()
        if !inside { hoverSuppressed = false }
        guard inside != state.expanded, !(inside && hoverSuppressed) else { return }
        let delay = inside ? UserDefaults.standard.double(forKey: Pref.hoverDelay) : 0.18
        hoverTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, hoverRect.contains(NSEvent.mouseLocation) == inside else { return }
            setExpanded(inside)
        }
    }

    private func updateVisibility(screen: NSScreen?) {
        let empty = store.primary == nil && state.approval == nil
        if empty || screen == nil || UserDefaults.standard.bool(forKey: Pref.hideBadge) { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Pending permission request → side blob (collapsed) or page (expanded); notify once per new request.
    /// Busy → pulsing blob, done → check blob.
    private func approvalsChanged() {
        let defaults = UserDefaults.standard
        let new = approvals.current.flatMap { defaults.bool(forKey: $0.isPlan ? Pref.planNotify : Pref.approvals) ? $0 : nil }
        if approvals.busy != state.busy || approvals.done != state.done {
            state.busy = approvals.busy
            state.done = approvals.done
            syncBlobs()
        }
        guard new != state.approval else { return }
        if let new, !new.isPlan, new.id != state.approval?.id { Notifier.post(title: "Claude", body: "\(new.tool) needs permission") }
        state.approval = new
        if state.expanded {
            if new != nil { setPage(.approval) } else if state.page == .approval { setPage(.overview) }
        }
        syncBlobs()
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

    private func setExpanded(_ on: Bool) {
        if (previewing || state.pinned) && !on { return }  // slider preview or pin holds the card open
        hoverTask?.cancel()
        guard on != state.expanded else { return }
        if on {
            if state.approval != nil { state.page = .approval }  // pending request opens on its own page
            state.cardShown = true
            canvas.cardVisible = true
            withAnimation(Motion.goo()) { state.expanded = true }
            present(delay: state.timerBlob || state.claudeBlob ? 0.1 : 0, fade: .in)  // blobs land first, then the card grows
        } else {
            withAnimation(Motion.goo(expanding: false)) { state.expanded = false }
            present(fade: .out)
            hoverSuppressed = hoverRect.contains(NSEvent.mouseLocation)
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

    private func setPage(_ page: Page) {
        guard page != state.page else { return }
        state.page = page
        if state.expanded { present() }
    }
}
