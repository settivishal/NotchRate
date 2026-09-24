import Charts
import SwiftUI

/// Bottom bar categories. Each owns one or more pages; swipe moves within a tab.
enum Tab: CaseIterable {
    case claude, caffeine, focus
    var title: String {
        switch self {
        case .claude: "Claude"
        case .caffeine: "Caffeinate"
        case .focus: "Focus"
        }
    }
    var icon: String {
        switch self {
        case .claude: "gauge.with.dots.needle.33percent"
        case .caffeine: "cup.and.saucer.fill"
        case .focus: "timer"
        }
    }
    var pages: [Page] { Page.allCases.filter { $0.tab == self && $0 != .approval } }  // approval page is opened by a request, never navigated to
}

enum Page: CaseIterable {
    case overview, trends, week, spend, caffeine, focus, approval
    var tab: Tab { self == .caffeine ? .caffeine : self == .focus ? .focus : .claude }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .trends: "Trends"
        case .week: "Week"
        case .spend: "Spend"
        case .caffeine: "Caffeinate"
        case .focus: "Focus"
        case .approval: "Approval"
        }
    }
}

@MainActor
@Observable
final class NotchState {
    var geometry: NotchGeometry
    var expanded = false
    var page = Page.overview
    var refreshing = false
    var pinned = false
    var tallCard = false  // overview shows a per-model row
    var approval: Approvals.Request?  // side blob with a countdown ring while set; hover opens the Allow/Deny page
    var busy = false                  // Claude Code is working on a prompt: pulsing blob
    var done = false                  // it finished and the terminal has not been opened since: check blob
    var busySince: Date?              // turn start, for the elapsed readout on the busy blob
    var spend: Spend?                 // API-value estimate from Claude Code's transcripts; nil until first read
    var notice: Notice?               // banner out of the closed island; drives its size and merges the blobs
    var noticeShown: Notice?          // what the banner draws: kept through the closing fade after `notice` clears
    var limitHit = false              // a rate-limit bucket is at 100%: red blob counting down to the reset
    var timerActive: Bool { focusing || caffeinated }
    var claudeActive: Bool { approval != nil || limitHit || busy || done }
    // Blob presence as drawn: follows timerActive/claudeActive inside withAnimation so pops animate.
    var timerBlob = false
    var claudeBlob = false
    var slack = false      // collapsed window keeps blob room until the last blob has popped back in
    var cardShown = false  // card content is rendered: from expand until the collapse spring settles
    /// nil = off, .distantFuture = until turned off, else auto-off at that time.
    var caffeineUntil: Date? {
        didSet {
            Caffeine.on = caffeinated
            if caffeinated != (oldValue != nil) { caffeineStarted = .now }
            onBlobChange?()
            schedule(&caffeineTimer, until: caffeineUntil) { $0.caffeineUntil = nil }
        }
    }
    var caffeinated: Bool { caffeineUntil != nil }
    var caffeineStarted = Date.now  // ring progress = remaining / (until - started)
    /// Pomodoro-style focus timer; notifies when it runs out.
    var focusUntil: Date? {
        didSet {
            if focusing != (oldValue != nil) { focusStarted = .now }
            onBlobChange?()
            schedule(&focusTimer, until: focusUntil) { s in
                s.focusUntil = nil
                Notifier.post(Notice(title: "Focus done", body: "\(Int(s.focusStarted.distance(to: .now) / 60)) min — take a break",
                                     icon: "timer", tint: .indigo, page: .focus))
            }
        }
    }
    var focusing: Bool { focusUntil != nil }
    var focusStarted = Date.now
    var onBlobChange: (() -> Void)?  // blobs come and go with the timers
    private var caffeineTimer: Task<Void, Never>?
    private var focusTimer: Task<Void, Never>?
    init(geometry: NotchGeometry) { self.geometry = geometry }

    private func schedule(_ timer: inout Task<Void, Never>?, until: Date?, _ fire: @escaping @MainActor (NotchState) -> Void) {
        timer?.cancel()
        guard let until, until != .distantFuture else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(until: .now + .seconds(until.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            fire(self)
        }
    }
}

/// Shared animations; AppKit side drives them through withAnimation.
@MainActor
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var card: Animation { reduce ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.86) }
    /// Blob merge: bouncier than the card, and on collapse it waits for the card to shrink before popping out.
    static func goo(expanding: Bool = true) -> Animation {
        let spring: Animation = reduce ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.78)
        return expanding ? spring : spring.delay(0.12)
    }
}

struct NotchView: View {
    /// Two hosting views share this view: the badge (goo body, side blobs, collapsed text) sits unmasked
    /// on top of the canvas; the card (tabs + pages) is masked by the canvas's moving silhouette.
    enum Part { case badge, card }
    let part: Part
    let store: UsageStore
    let state: NotchState
    var setExpanded: (Bool) -> Void
    var setPage: (Page) -> Void
    var refresh: () -> Void
    var togglePin: () -> Void
    var answer: (Approvals.Request, String) -> Void  // "allow", "allow <mode>", "deny"
    var clearDone: () -> Void

    @AppStorage(Pref.staleHours) private var staleHours = 2.0
    @AppStorage(Pref.showWeekly) private var showWeekly = false
    @AppStorage(Pref.ringGauges) private var ringGauges = true
    @AppStorage(Pref.pollSeconds) private var pollSeconds = 60.0
    @AppStorage(Pref.cardRadius) private var cardRadius = 28.0
    @AppStorage(Pref.badgeCountdown) private var badgeCountdown = false
    @AppStorage(Pref.badgeRing) private var badgeRing = false
    @AppStorage(Pref.blobLeft) private var blobLeft = false
    @AppStorage(Pref.cardSize) private var cardSize = "compact"  // re-render on preset change
    @AppStorage(Pref.cardScale) private var cardScale = 1.25

    var body: some View {
        Group {
            switch part {
            case .badge: ticking { badge(now: $0) }
            case .card:
                if state.cardShown {
                    if !state.expanded, let n = state.noticeShown { noticeBanner(n) } else { ticking { card(now: $0) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pointerStyle(.default)  // no I-beam over labels
    }

    /// 1 s ticks only while something counts down (approval expiry, caffeine ring/timer).
    private func ticking<V: View>(@ViewBuilder _ content: @escaping (Date) -> V) -> some View {
        TimelineView(.periodic(from: .now, by: state.approval == nil && !state.caffeinated && !state.focusing && !state.busy ? 60 : 1)) { content($0.date) }
    }

    /// Collapsed notch body with the side blobs. Timer blob (focus, else caffeine) on one side (setting), Claude
    /// activity (approval, else limit, else busy, else done) on the other. A side is "merged" (1) while its blob
    /// is absent or the card is open.
    private func badge(now: Date) -> some View {
        let geo = state.geometry
        let size = geo.collapsedSize(blob: state.slack)
        let open = state.expanded || state.notice != nil
        let claudeMerge: CGFloat = open || !state.claudeBlob ? 1 : 0
        let timerMerge: CGFloat = open || !state.timerBlob ? 1 : 0
        return ZStack(alignment: .top) {
            GooBody(shape: .forHeight(geo.topHeight, notch: geo.hasNotch, cardRadius: cardRadius),
                    blob: geo.blobWidth, gap: NotchGeometry.blobGap, slack: state.slack,
                    left: blobLeft ? timerMerge : claudeMerge, right: blobLeft ? claudeMerge : timerMerge)
            if state.timerBlob {
                sideBlob(leading: blobLeft) {
                    if state.focusing { focusBlob(now: now) } else if state.caffeinated { caffeineBlob(now: now) }
                }
            }
            if state.claudeBlob {
                sideBlob(leading: !blobLeft) {
                    if let r = state.approval { approvalBlob(r, now: now) }
                    else if state.limitHit, let snap = store.primary { limitBlob(snap, now: now) }
                    else if state.busy { busyBlob(now: now) }
                    else if state.done { doneBlob }
                }
            }
            if !state.expanded, let snap = store.primary {
                collapsed(snap, level: snap.level(now: now, staleAfter: staleHours * 3600), now: now)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Tab bar + page, laid out once at the page's final size; the canvas springs the silhouette around it.
    private func card(now: Date) -> some View {
        let geo = state.geometry
        let size = geo.expandedSize(for: state.page, tall: state.tallCard, plan: state.approval?.isPlan == true)
        let snap = store.primary  // Claude pages need usage data; the other tabs do not
        // Even black margin all round: the sides also clear the shoulder flare at the top corners.
        let side = NotchShape.forHeight(size.height, notch: geo.hasNotch, cardRadius: cardRadius).topRadius + NotchGeometry.cardMargin
        return VStack(spacing: 0) {
            // Tab bar sits right under the notch: the card resizes from the bottom, so the
            // cursor stays inside while switching pages (a bottom bar slid out from under it).
            Color.clear.frame(height: geo.topHeight)
            tabBar(inset: side)
            Group {
                switch state.page {
                case .overview where snap != nil: expanded(snap!, level: snap!.level(now: now, staleAfter: staleHours * 3600), now: now)
                case .trends where snap != nil: trends(snap!, now: now)
                case .week where snap != nil: week(snap!, now: now)
                case .spend: spendPage(now: now)
                case .overview, .trends, .week:
                    Text("No usage data yet").font(.caption).foregroundStyle(.secondary).frame(maxHeight: .infinity)
                case .caffeine: caffeinePage(now: now)
                case .focus: focusPage(now: now)
                case .approval: approvalPage(now: now)
                }
            }
            .frame(width: size.width - 2 * side)  // a too-wide row sticks out alone instead of widening every row
            .padding(.bottom, NotchGeometry.cardMargin)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(Motion.card, value: state.page)
    }

    /// One row under the notch: icon, title and detail. A click opens the card on the notice's page.
    private func noticeBanner(_ n: Notice) -> some View {
        let geo = state.geometry, size = geo.noticeSize
        let side = NotchShape.forHeight(size.height, notch: geo.hasNotch, cardRadius: cardRadius).topRadius + NotchGeometry.cardMargin
        return VStack(spacing: 0) {
            Color.clear.frame(height: geo.topHeight)
            HStack(spacing: 10) {
                Image(systemName: n.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(n.tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(n.body).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, side)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if let p = n.page { setPage(p) }
            setExpanded(true)
        }
    }

    // MARK: side blobs

    /// Detached circle beside the badge, iOS Dynamic Island style; rides the goo circle into and out of the notch.
    private func sideBlob<V: View>(leading: Bool, @ViewBuilder _ content: () -> V) -> some View {
        let travel = state.geometry.blobWidth + NotchGeometry.blobGap
        let shown = !state.expanded
        let inward = AnyTransition.offset(x: leading ? travel : -travel).combined(with: .opacity)
        return content()
            .padding(5)
            .frame(width: state.geometry.blobWidth, height: state.geometry.blobWidth)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .offset(x: shown ? 0 : leading ? travel : -travel)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .transition(inward)
    }

    /// Ring counts down `progress` 1 → 0 around `icon`.
    private func ringBlob(progress: Double, icon: String, tint: Color) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: icon).resizable().scaledToFit().frame(width: state.geometry.blobWidth * 0.24).foregroundStyle(tint)
        }
    }

    /// Permission request: ring runs out as the hook's wait expires, then the terminal prompt has it.
    private func approvalBlob(_ r: Approvals.Request, now: Date) -> some View {
        let expired = now >= r.expires
        let progress = max(0, min(1, r.expires.timeIntervalSince(now) / (r.isPlan ? Approvals.planWait : Approvals.wait)))
        return ringBlob(progress: progress, icon: expired ? "terminal" : r.isPlan ? "list.bullet.clipboard" : "exclamationmark.shield.fill", tint: expired ? .gray : .orange)
            .onTapGesture { setPage(.approval); setExpanded(true) }
    }

    private func focusBlob(now: Date) -> some View {
        let progress = state.focusUntil.map { max(0, min(1, $0.timeIntervalSince(now) / $0.timeIntervalSince(state.focusStarted))) } ?? 0
        return ringBlob(progress: progress, icon: "timer", tint: .indigo)
            .onTapGesture { setPage(.focus); setExpanded(true) }
    }

    /// A bucket is at 100%: ring drains as its window runs out.
    private func limitBlob(_ snap: UsageSnapshot, now: Date) -> some View {
        let session = (snap.sessionUsedPct ?? 0) >= 100
        let resets = (session ? snap.sessionResetsAt : snap.weeklyResetsAt) ?? now.timeIntervalSince1970
        let progress = max(0, min(1, (resets - now.timeIntervalSince1970) / (session ? 5 * 3600 : 7 * 86400)))
        return ringBlob(progress: progress, icon: "hourglass", tint: .red)
            .onTapGesture { setPage(.overview); setExpanded(true) }
    }

    /// Elapsed turn time once known ("42s", "3m", "1h"), else the pulsing sparkle.
    private func busyBlob(now: Date) -> some View {
        Group {
            if let since = state.busySince {
                let secs = max(0, Int(now.timeIntervalSince(since)))
                Text(secs < 60 ? "\(secs)s" : secs < 3600 ? "\(secs / 60)m" : "\(secs / 3600)h")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit().frame(width: state.geometry.blobWidth * 0.28)
                    .symbolEffect(.pulse)
            }
        }
        .foregroundStyle(.white)
        .onTapGesture { setPage(.overview); setExpanded(true) }
    }

    /// Persists until a terminal app comes to the front (or a click).
    private var doneBlob: some View {
        Image(systemName: "checkmark").resizable().scaledToFit().frame(width: state.geometry.blobWidth * 0.24)
            .fontWeight(.bold).foregroundStyle(.green)
            .onTapGesture { clearDone() }
    }

    /// Full request with the terminal's choices. Plans get the markdown and the three ExitPlanMode options.
    private func approvalPage(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = state.approval {
                header(status: now < r.expires ? "\(relative(r.expires.timeIntervalSince1970, now: now)) left" : "answer in terminal")
                HStack(spacing: 6) {
                    Image(systemName: r.isPlan ? "list.bullet.clipboard" : "exclamationmark.shield.fill").foregroundStyle(.orange)
                    Text(r.isPlan ? "Plan ready for review" : "\(r.tool) needs permission").font(.caption).bold()
                }
                if let plan = r.plan {
                    ScrollView {
                        Text(planText(plan))
                            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else if !r.detail.isEmpty {
                    Text(r.detail).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if now < r.expires {
                    HStack(spacing: 6) {
                        if r.isPlan {
                            NavButton(icon: "checkmark", label: "Auto-accept edits", tint: .green) { answer(r, "allow acceptEdits") }
                            NavButton(icon: "checkmark", label: "Ask on edits", tint: .green) { answer(r, "allow default") }
                            NavButton(icon: "xmark", label: "Keep planning", tint: .red) { answer(r, "deny") }
                        } else {
                            NavButton(icon: "checkmark", label: "Allow", tint: .green) { answer(r, "allow") }
                            NavButton(icon: "xmark", label: "Deny", tint: .red) { answer(r, "deny") }
                        }
                    }
                }
            } else {
                Text("Nothing pending").font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    // MARK: tab bar + caffeinate

    private func tabBar(inset: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { t in
                // Running timers glow on every tab so the state is visible from Claude too.
                let glow: Color? = t == .caffeine && state.caffeinated ? .orange : t == .focus && state.focusing ? .indigo : nil
                NavButton(icon: t.icon, label: t.title, large: true, tint: glow ?? (state.page.tab == t ? .white : nil)) { setPage(t.pages[0]) }
                    .shadow(color: glow?.opacity(0.8) ?? .clear, radius: 6)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {  // logo in the corner, aligned with the page margin
            Image(nsImage: Brand.glyph).renderingMode(.template).resizable().scaledToFit().frame(height: 16)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, inset)
        }
    }

    /// Orange ring counts down the caffeine timer, cup inside.
    private func caffeineBlob(now: Date) -> some View {
        let progress: Double = state.caffeineUntil.map { until in
            until == .distantFuture ? 1 : max(0, min(1, until.timeIntervalSince(now) / until.timeIntervalSince(state.caffeineStarted)))
        } ?? 0
        return ringBlob(progress: progress, icon: "cup.and.saucer.fill", tint: .orange)
            .onTapGesture { setPage(.caffeine); setExpanded(true) }
    }

    private func caffeinePage(now: Date) -> some View {
        timerPage(now: now, until: state.caffeineUntil, tint: .orange, offIcon: "moon",
                  status: state.caffeinated ? "Mac stays awake" : "sleeping normally",
                  presets: [("30m", 1800), ("1h", 3600), ("2h", 7200), ("∞", .infinity)]) { state.caffeineUntil = $0 }
    }

    private func focusPage(now: Date) -> some View {
        timerPage(now: now, until: state.focusUntil, tint: .indigo, offIcon: "stop.fill",
                  status: state.focusing ? "focusing · notifies when done" : "idle",
                  presets: [("15m", 900), ("25m", 1500), ("45m", 2700), ("1h", 3600)]) { state.focusUntil = $0 }
    }

    /// Big countdown (∞ for "until turned off") over an Off button and duration presets.
    private func timerPage(now: Date, until: Date?, tint: Color, offIcon: String, status: String,
                           presets: [(String, TimeInterval)], set: @escaping (Date?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: status)
            Text(until.map { $0 == .distantFuture ? "∞" : countdown($0, now: now) } ?? "OFF")
                .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(until != nil ? tint : .gray)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            HStack(spacing: 8) {
                NavButton(icon: offIcon, label: "Off", large: true, tint: until == nil ? .white : nil) { set(nil) }
                ForEach(presets, id: \.0) { name, secs in
                    let target: Date = secs.isInfinite ? .distantFuture : now.addingTimeInterval(secs)
                    let selected = until.map { secs.isInfinite ? $0 == .distantFuture : abs($0.timeIntervalSince(target)) < 60 } ?? false
                    NavButton(label: name, large: true, tint: selected ? tint : nil) { set(target) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    // MARK: collapsed

    private func collapsed(_ snap: UsageSnapshot, level: Level, now: Date) -> some View {
        let geo = state.geometry
        let stale = level == .stale
        let session = stale ? .stale : Level(pct: snap.sessionUsedPct ?? 0)
        let weekly = stale ? .stale : Level(pct: snap.weeklyUsedPct ?? 0)
        // 14pt pads keep text clear of the bottom corner curves.
        return HStack(spacing: 0) {
            Group {
                if showWeekly {
                    bucket("5h", snap.sessionUsedPct, resets: snap.sessionResetsAt, level: session, now: now).padding(.leading, geo.hasNotch ? 14 : 0)
                } else {
                    // Group is transparent to the HStack: the wing frame applies per child, so keep the dot and cup in one HStack.
                    HStack(spacing: 5) {
                        if badgeRing {
                            ZStack {
                                Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                                Circle().trim(from: 0, to: min(snap.sessionUsedPct ?? 0, 100) / 100)
                                    .stroke(session.color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                            }
                            .frame(width: 10, height: 10)
                        } else {
                            Circle().fill(session.color).frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .frame(width: geo.hasNotch ? geo.wingWidth : 30)
            if geo.hasNotch { Color.clear.frame(width: geo.notchWidth) }
            Group {
                if showWeekly {
                    bucket("7d", snap.weeklyUsedPct, resets: snap.weeklyResetsAt, level: weekly, now: now)
                } else {
                    pctText(snap.sessionUsedPct, resets: snap.sessionResetsAt, stale: stale, now: now)
                }
            }
            .padding(.trailing, geo.hasNotch ? 14 : 0)
            .frame(width: geo.hasNotch ? geo.wingWidth : nil, alignment: geo.hasNotch ? .center : .leading)
        }
        .frame(height: geo.topHeight)
        .opacity(stale ? 0.5 : 1)
    }

    /// Caption carries the color so no dot is needed.
    private func bucket(_ label: String, _ pct: Double?, resets: Double?, level: Level, now: Date) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(level.color)
            pctText(pct, resets: resets, stale: level == .stale, now: now)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }

    /// Percent, or time to reset in countdown mode.
    private func pctText(_ pct: Double?, resets: Double?, stale: Bool, now: Date) -> some View {
        let text = badgeCountdown ? resets.map { relative($0, now: now) } ?? "—" : pct.map { "\(Int($0.rounded()))%" } ?? "—"
        return Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(stale ? .gray : .white)
    }

    // MARK: expanded

    private func expanded(_ snap: UsageSnapshot, level: Level, now: Date) -> some View {
        let stale = level == .stale
        return VStack(alignment: .leading, spacing: 12) {
            header(status: stale ? "offline · \(relative(snap.lastUpdated, now: now)) ago"
                   : now.timeIntervalSince1970 - snap.lastUpdated < 2 * max(30, pollSeconds) ? "live" : "updated \(relative(snap.lastUpdated, now: now)) ago") {
                NavButton(icon: "arrow.clockwise", spinning: state.refreshing, action: refresh)
                NavButton(icon: state.pinned ? "pin.fill" : "pin", action: togglePin)
            }
            if ringGauges {
                HStack(spacing: 0) {
                    ring("Session", snap.sessionUsedPct, resets: snap.sessionResetsAt, now: now, stale: stale)
                    ring("Weekly", snap.weeklyUsedPct, resets: snap.weeklyResetsAt, now: now, stale: stale)
                }
            } else {
                bar("Session", snap.sessionUsedPct, resets: snap.sessionResetsAt, now: now)
                bar("Weekly", snap.weeklyUsedPct, resets: snap.weeklyResetsAt, now: now)
            }
            if let models = snap.models, !models.isEmpty {
                HStack(spacing: 14) {
                    ForEach(models.keys.sorted(), id: \.self) { name in
                        let b = models[name]!
                        HStack(spacing: 4) {
                            Text(name.capitalized).font(.caption2).foregroundStyle(.secondary)
                            Text("\(Int(b.pct.rounded()))%").font(.caption2).monospacedDigit().foregroundStyle(Level(pct: b.pct).color)
                        }
                    }
                    Spacer()
                }
            }
            Divider().overlay(.white.opacity(0.15))
            HStack {
                Text(snap.costUsd.map { $0.formatted(.currency(code: "USD")) + " spent" } ?? "—")
                Spacer()
                Text("\(Int((snap.contextPct ?? 0).rounded()))% context")
                Spacer()
                if let extra = snap.extraPct {
                    Text("\(Int(extra.rounded()))% extra")
                    Spacer()
                }
                NavButton(icon: "arrow.up.right", label: "usage") { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .opacity(stale ? 0.6 : 1)
        .transition(.opacity)
    }

    /// Title row: sub-page pills when the tab has several pages, else the page title.
    /// Title row: sub-page pills when the tab has several pages, else the page title; then status text and
    /// actions. The status text is dropped (kept as a tooltip) before the row can outgrow the card: an
    /// overflowing row would widen every page past the silhouette.
    private func header<Actions: View>(status: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        let actions = actions()
        return ViewThatFits(in: .horizontal) {
            headerRow(status: status, actions: actions)
            headerRow(status: nil, actions: actions).help(status ?? "")
        }
    }

    private func header(status: String? = nil) -> some View { header(status: status) { EmptyView() } }

    private func headerRow(status: String?, actions: some View) -> some View {
        let pages = state.page.tab.pages
        return HStack(spacing: 6) {
            if pages.count > 1, pages.contains(state.page) {
                ForEach(pages, id: \.self) { p in
                    NavButton(label: p.title, tint: state.page == p ? .white : nil) { setPage(p) }
                }
            } else {
                Text(state.page.title).font(.headline)
            }
            Spacer(minLength: 4)
            if let status { Text(status).font(.caption).foregroundStyle(.gray).lineLimit(1) }
            actions
        }
    }

    // MARK: trends

    private func trends(_ snap: UsageSnapshot, now: Date) -> some View {
        let rows = History.load(now: now)
        let s = snap.sessionUsedPct ?? 0, w = snap.weeklyUsedPct ?? 0
        let sRate = History.rate(rows, \.s, hours: 1, now: now)
        let used = History.usedThisWindow(rows)
        let stats = WeekStats(rows, weeklyResetsAt: snap.weeklyResetsAt, now: now)
        let inWindow = rows.filter { $0.ts >= now.timeIntervalSince1970 - 7 * 86400 }.count
        return VStack(alignment: .leading, spacing: 4) {
            header()
            label("Session", s, resets: snap.sessionResetsAt, now: now,
                  detail: sRate > 0 ? "\(Int(sRate.rounded()))%/h · full in ~\(hours((100 - s) / sRate)) · +\(Int(used.rounded()))% this window" : "idle · +\(Int(used.rounded()))% this window")
            chart(rows, \.s, hours: 5, pct: s, now: now)
            label("Weekly", w, resets: snap.weeklyResetsAt, now: now,
                  detail: "today \(Int((stats.daily.last?.pct ?? 0).rounded()))% · avg \(Int(stats.avgPerDay.rounded()))%/day · projected \(Int(stats.projected.rounded()))%",
                  warn: stats.projected >= 100)
            chart(rows, \.w, hours: 24 * 7, pct: w, now: now)
            if inWindow < 20 {
                Text("collecting data · \(inWindow) samples").font(.caption2).foregroundStyle(.gray)
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private func label(_ title: String, _ pct: Double, resets: Double?, now: Date, detail: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("\(title) \(Int(pct.rounded()))%").font(.caption).bold()
                if let resets { Text("· resets \(resetText(resets, now: now))").font(.caption).foregroundStyle(.secondary) }
            }
            Text(detail).font(.caption2).foregroundStyle(warn ? .red : .secondary)
        }
        .padding(.top, 4)
    }

    private func chart(_ rows: [Sample], _ key: KeyPath<Sample, Double?>, hours: Double, pct: Double, now: Date) -> some View {
        let start = now.addingTimeInterval(-hours * 3600)
        let pts = rows.filter { $0.ts >= start.timeIntervalSince1970 && $0.ts <= now.timeIntervalSince1970 }
            .compactMap { r in r[keyPath: key].map { (Date(timeIntervalSince1970: r.ts), $0) } }
        let color = Level(pct: pct).color
        let step: TimeInterval = hours > 24 ? 2 * 86400 : 2 * 3600
        let ticks = stride(from: 0.0, through: hours * 3600, by: step).map { now.addingTimeInterval(-$0) }
        return Chart {
            ForEach(pts, id: \.0) { p in
                AreaMark(x: .value("t", p.0), y: .value("%", p.1))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", p.0), y: .value("%", p.1))
                    .foregroundStyle(color).lineStyle(.init(lineWidth: 1.5)).interpolationMethod(.monotone)
            }
            RuleMark(y: .value("limit", 100)).foregroundStyle(.white.opacity(0.2)).lineStyle(.init(lineWidth: 0.5, dash: [3]))
        }
        .chartYScale(domain: 0...100).chartYAxis(.hidden)
        .chartXScale(domain: start...now)
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisValueLabel { Text(ago(now.timeIntervalSince(v.as(Date.self)!))).font(.caption2).foregroundStyle(.gray) }
            }
        }
        .frame(height: 70 * NotchGeometry.scale)
    }

    private func ago(_ secs: TimeInterval) -> String {
        secs < 60 ? "now" : secs < 86400 ? "\(Int(secs / 3600))h ago" : "\(Int(secs / 86400))d ago"
    }

    private func hours(_ h: Double) -> String {
        h < 1 ? "\(Int((h * 60).rounded()))m" : "\(Int(h.rounded()))h"
    }

    // MARK: week

    private func week(_ snap: UsageSnapshot, now: Date) -> some View {
        let stats = WeekStats(History.load(now: now), weeklyResetsAt: snap.weeklyResetsAt, now: now)
        let today = Calendar.current.startOfDay(for: now)
        return VStack(alignment: .leading, spacing: 12) {
            header(status: snap.weeklyResetsAt.map { "resets \(resetText($0, now: now))" })
            Chart(stats.daily, id: \.day) { d in
                BarMark(x: .value("day", d.day, unit: .day), y: .value("%", d.pct))
                    .foregroundStyle(d.day == today ? Color.accentColor : .white.opacity(0.35))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        Text(d.pct > 0 ? "\(Int(d.pct.rounded()))%" : "—").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true) } }
            .chartYAxis(.hidden)
            .frame(height: 120 * NotchGeometry.scale)
            Divider().overlay(.white.opacity(0.15))
            Group {
                HStack {
                    Text("Projected at reset: \(Int(stats.projected.rounded()))%").foregroundStyle(stats.projected >= 100 ? .red : .secondary)
                    Spacer()
                    Text("Peak 5h: \(Int(stats.peakSession.rounded()))%")
                }
                HStack {
                    Text("Sessions: \(stats.sessions)")
                    Spacer()
                    Text("Hit limit: \(stats.hitLimit)×")
                    Spacer()
                    Text("CLI \(stats.cliCost.formatted(.currency(code: "USD")))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    // MARK: spend

    /// What the logged tokens would cost at API list prices, with where it went and a 13-week activity map.
    private func spendPage(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(status: "API value · est.")
            if let s = state.spend {
                HStack {
                    stat("Today", s.today)
                    stat("7 days", s.week)
                    stat("30 days", s.month)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        breakdown(s.byModel.prefix(3), total: s.month)
                        breakdown(s.byProject.prefix(3), total: s.month)
                    }
                    heatmap(s.daily, now: now)
                }
                Text([s.cacheHit.map { "\(Int(($0 * 100).rounded()))% of prompt tokens from cache" },
                      s.unpriced > 0 ? "\(s.unpriced) unpriced" : nil].compactMap(\.self).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.gray)
            } else {
                Text("Reading Claude Code logs…").font(.caption).foregroundStyle(.secondary).frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private func stat(_ title: String, _ dollars: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dollars.formatted(.currency(code: "USD").precision(.fractionLength(dollars < 100 ? 2 : 0))))
                .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Name, share bar and cost; shares are of the 30-day total.
    private func breakdown(_ rows: ArraySlice<Spend.Row>, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.name) { r in
                HStack(spacing: 6) {
                    Text(r.name).font(.caption2).lineLimit(1).truncationMode(.middle).frame(width: 64, alignment: .leading)
                    Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(Color.accentColor).frame(width: g.size.width * (total > 0 ? r.cost / total : 0)) }
                        }
                    Text(r.cost.formatted(.currency(code: "USD").precision(.fractionLength(0)))).font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    /// 13 weeks × 7 days, oldest top-left, today bottom-right; brightness scales with the day's cost.
    private func heatmap(_ daily: [Date: Double], now: Date) -> some View {
        let cal = Calendar.current, today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7  // today's row
        let peak = max(daily.values.max() ?? 0, 0.01)
        return HStack(spacing: 2) {
            ForEach(0..<13, id: \.self) { col in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { row in
                        let back = (12 - col) * 7 + (weekday - row)
                        let day = cal.date(byAdding: .day, value: -back, to: today)!
                        let cost = daily[day] ?? 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(back < 0 ? .clear : cost > 0 ? Color.accentColor.opacity(0.25 + 0.75 * cost / peak) : .white.opacity(0.08))
                            .frame(width: 8 * NotchGeometry.scale, height: 8 * NotchGeometry.scale)
                            .help(back < 0 ? "" : "\(day.formatted(.dateTime.month(.abbreviated).day())): \(cost.formatted(.currency(code: "USD")))")
                    }
                }
            }
        }
    }

    private func ring(_ title: String, _ pct: Double?, resets: Double?, now: Date, stale: Bool) -> some View {
        let v = pct ?? 0
        let color = stale ? Level.stale.color : Level(pct: v).color
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: min(v, 100) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(pct == nil ? "—" : "\(Int(v.rounded()))")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).bold()
                Text(v >= 100 ? "limit reached" : resets.map { "resets \(resetText($0, now: now))" } ?? "—")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { setPage(.trends) }
    }

    private func bar(_ title: String, _ pct: Double?, resets: Double?, now: Date) -> some View {
        let v = pct ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(pct == nil ? "—" : "\(Int(v.rounded()))%").font(.caption).monospacedDigit()
                if let resets { Text("· resets \(resetText(resets, now: now))").font(.caption2).foregroundStyle(.secondary) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(Level(pct: v).color).frame(width: g.size.width * min(v, 100) / 100)
                }
            }
            .frame(height: 5)
        }
    }

    private func resetText(_ epoch: Double, now: Date) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "now" }
        if secs < 24 * 3600 { return "in " + relative(epoch, now: now) }
        return date.formatted(.dateTime.weekday(.abbreviated).hour())
    }

    /// Headings bold + white, inline markdown for the rest; blank lines kept.
    private func planText(_ plan: String) -> AttributedString {
        var out = AttributedString()
        for (i, line) in plan.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if i > 0 { out += AttributedString("\n") }
            let str = String(line)
            if let range = str.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                var h = AttributedString(str[range.upperBound...])
                h.font = .caption.bold()
                h.foregroundColor = .white
                out += h
            } else {
                out += (try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(str)
            }
        }
        return out
    }

    /// h:mm:ss for the caffeine timer.
    private func countdown(_ until: Date, now: Date) -> String {
        let secs = max(0, Int(until.timeIntervalSince(now)))
        return secs >= 3600 ? String(format: "%d:%02d:%02d", secs / 3600, secs % 3600 / 60, secs % 60) : String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private func relative(_ epoch: Double, now: Date) -> String {
        let secs = Int(abs(now.timeIntervalSince1970 - epoch))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// Small pill that lights up and shows a hand cursor on hover; chevrons alone were easy to miss.
struct NavButton: View {
    var icon: String? = nil
    var label: String? = nil
    var spinning = false
    var large = false        // caffeine presets: taller pill, bigger text
    var tint: Color? = nil  // resting color; default gray
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            if let label { Text(label).font(large ? .callout.weight(.semibold) : .caption) }
            if let icon {
                Image(systemName: icon).resizable().scaledToFit().fontWeight(.bold)
                    .frame(width: 11, height: 11)  // every glyph fills the same box
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: spinning)
            }
        }
        .foregroundStyle(hovered ? .white : tint ?? .gray)
        .padding(.horizontal, label == nil ? 0 : large ? 14 : 9)
        .frame(width: label == nil ? 24 : nil, height: large ? 32 : 24)
        .background((tint ?? .white).opacity(hovered ? 0.3 : 0.1), in: Capsule())
        .scaleEffect(hovered ? 1.06 : 1)
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .pointerStyle(.default)  // solid arrow; push/pop of NSCursor was overridden in the non-key panel
        .animation(.easeOut(duration: 0.07), value: hovered)
    }
}

