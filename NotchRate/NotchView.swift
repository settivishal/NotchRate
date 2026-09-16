import Charts
import SwiftUI

/// Bottom bar categories. Each owns one or more pages; swipe moves within a tab.
enum Tab: CaseIterable {
    case claude, caffeine
    var icon: String {
        switch self {
        case .claude: "gauge.with.dots.needle.33percent"
        case .caffeine: "cup.and.saucer.fill"
        }
    }
    var pages: [Page] { Page.allCases.filter { $0.tab == self && $0 != .approval } }  // approval page is opened by a request, never navigated to
}

enum Page: CaseIterable {
    case overview, trends, week, caffeine, approval
    var tab: Tab { self == .caffeine ? .caffeine : .claude }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .trends: "Trends"
        case .week: "Week"
        case .caffeine: "Caffeinate"
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
    var approval: Approvals.Request?  // collapsed badge becomes an Allow/Deny island while set
    /// nil = off, .distantFuture = until turned off, else auto-off at that time.
    var caffeineUntil: Date? {
        didSet {
            Caffeine.on = caffeinated
            if caffeinated != (oldValue != nil) { caffeineStarted = .now }
            onCaffeineChange?()
            caffeineTimer?.cancel()
            guard let until = caffeineUntil, until != .distantFuture else { return }
            caffeineTimer = Task { [weak self] in
                try? await Task.sleep(until: .now + .seconds(until.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.caffeineUntil = nil
            }
        }
    }
    var caffeinated: Bool { caffeineUntil != nil }
    var caffeineStarted = Date.now  // ring progress = remaining / (until - started)
    var onCaffeineChange: (() -> Void)?  // collapsed window width changes with the blob
    private var caffeineTimer: Task<Void, Never>?
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

struct NotchView: View {
    let store: UsageStore
    let state: NotchState
    var setExpanded: (Bool) -> Void
    var setPage: (Page) -> Void
    var refresh: () -> Void
    var togglePin: () -> Void
    var answer: (Approvals.Request, String) -> Void  // "allow", "allow <mode>", "deny"

    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.3
    @AppStorage(Pref.staleHours) private var staleHours = 2.0
    @AppStorage(Pref.showWeekly) private var showWeekly = false
    @AppStorage(Pref.ringGauges) private var ringGauges = true
    @AppStorage(Pref.pollSeconds) private var pollSeconds = 60.0
    @AppStorage(Pref.cardRadius) private var cardRadius = 28.0
    @AppStorage(Pref.badgeCountdown) private var badgeCountdown = false
    @AppStorage(Pref.badgeRing) private var badgeRing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTask: Task<Void, Never>?

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.8)
    }

    var body: some View {
        let geo = state.geometry
        let size = state.expanded ? geo.expandedSize(for: state.page, tall: state.tallCard, plan: state.approval?.isPlan == true)
                                  : geo.collapsedSize(island: state.approval != nil, blob: state.caffeinated)
        TimelineView(.periodic(from: .now, by: state.approval == nil && !(state.expanded && state.page == .caffeine) ? 60 : 1)) { ctx in
            let blob = !state.expanded && state.caffeinated
            ZStack(alignment: .top) {
                NotchShape(topRadius: geo.hasNotch ? 6 : 0, bottomRadius: state.expanded ? cardRadius : 12)
                    .fill(.black)
                    .padding(.horizontal, blob ? geo.blobWidth + NotchGeometry.blobGap : 0)  // leave room for the side blob
                if blob {
                    caffeineBlob(now: ctx.date)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if state.expanded, let snap = store.primary {
                    let level = snap.level(now: ctx.date, staleAfter: staleHours * 3600)
                    VStack(spacing: 0) {
                        // Tab bar sits right under the notch: the card resizes from the bottom, so the
                        // cursor stays inside while switching pages (a bottom bar slid out from under it).
                        Color.clear.frame(height: geo.topHeight)
                        tabBar
                        switch state.page {
                        case .overview: expanded(snap, level: level, now: ctx.date)
                        case .trends: trends(snap, now: ctx.date)
                        case .week: week(snap, now: ctx.date)
                        case .caffeine: caffeinePage(now: ctx.date)
                        case .approval: approvalPage(now: ctx.date)
                        }
                    }
                } else if let r = state.approval {
                    island(r, now: ctx.date)
                } else if let snap = store.primary {
                    collapsed(snap, level: snap.level(now: ctx.date, staleAfter: staleHours * 3600), now: ctx.date)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .pointerStyle(.default)  // no I-beam over labels
            .animation(animation, value: state.expanded)
            .animation(animation, value: state.page)
            .onHover(perform: hover)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            guard store.primary != nil else { return }
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(hoverDelay))
                guard !Task.isCancelled else { return }
                setExpanded(true)
            }
        } else {
            setExpanded(false)
        }
    }

    // MARK: island

    /// Permission request from Claude Code. Buttons vanish once the hook gave up and the terminal prompt took over.
    private func island(_ r: Approvals.Request, now: Date) -> some View {
        let geo = state.geometry
        let wing = geo.hasNotch ? NotchGeometry.islandWing : nil
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: r.isPlan ? "list.bullet.clipboard" : "exclamationmark.shield.fill").foregroundStyle(.orange)
                Text(r.isPlan ? "Plan ready" : r.tool).lineLimit(1).minimumScaleFactor(0.6)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .padding(.leading, geo.hasNotch ? 12 : 0)
            .frame(width: wing)
            if geo.hasNotch { Color.clear.frame(width: geo.notchWidth) }
            Group {
                if now >= r.expires {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal").font(.caption)
                        Text("in terminal").font(.caption2)
                    }
                    .foregroundStyle(.gray)
                } else if r.isPlan {
                    Text("hover to review").font(.caption2).foregroundStyle(.gray)
                } else {
                    HStack(spacing: 6) {
                        NavButton(icon: "checkmark", tint: .green) { answer(r, "allow") }
                        NavButton(icon: "xmark", tint: .red) { answer(r, "deny") }
                    }
                }
            }
            .padding(.trailing, geo.hasNotch ? 12 : 0)
            .frame(width: wing, alignment: geo.hasNotch ? .center : .leading)
        }
        .frame(height: geo.topHeight)
    }

    /// Full request with the terminal's choices. Plans get the markdown and the three ExitPlanMode options.
    private func approvalPage(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = state.approval {
                header {
                    Text(now < r.expires ? "\(relative(r.expires.timeIntervalSince1970, now: now)) left" : "answer in terminal")
                }
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
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    // MARK: tab bar + caffeinate

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { t in
                let awake = t == .caffeine && state.caffeinated  // glows on every tab so the state is visible from Claude too
                NavButton(icon: t.icon, tint: awake ? .orange : state.page.tab == t ? .white : nil) { setPage(t.pages[0]) }
                    .shadow(color: awake ? .orange.opacity(0.8) : .clear, radius: 6)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Detached circle beside the badge, iOS Dynamic Island style: orange ring counts down, cup inside.
    private func caffeineBlob(now: Date) -> some View {
        let d = state.geometry.blobWidth
        let progress: Double = state.caffeineUntil.map { until in
            until == .distantFuture ? 1 : max(0, min(1, until.timeIntervalSince(now) / until.timeIntervalSince(state.caffeineStarted)))
        } ?? 0
        return ZStack {
            Circle().fill(.black)
            Circle().stroke(.orange.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress)
                .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: "cup.and.saucer.fill").resizable().scaledToFit().frame(width: d * 0.38).foregroundStyle(.orange)
        }
        .padding(5)
        .frame(width: d, height: d)
        .onTapGesture { setPage(.caffeine); setExpanded(true) }
    }

    private static let presets: [(String, TimeInterval)] = [("30m", 1800), ("1h", 3600), ("2h", 7200), ("∞", .infinity)]

    private func caffeinePage(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header { Text(state.caffeinated ? "Mac stays awake" : "sleeping normally") }
            // Big countdown in the middle; ∞ for "until turned off".
            Text(state.caffeineUntil.map { $0 == .distantFuture ? "∞" : countdown($0, now: now) } ?? "OFF")
                .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(state.caffeinated ? .orange : .gray)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            HStack(spacing: 8) {
                NavButton(icon: "moon", label: "Off", large: true, tint: state.caffeinated ? nil : .white) { state.caffeineUntil = nil }
                ForEach(Self.presets, id: \.0) { name, secs in
                    let target: Date = secs.isInfinite ? .distantFuture : now.addingTimeInterval(secs)
                    let selected = state.caffeineUntil.map { secs.isInfinite ? $0 == .distantFuture : abs($0.timeIntervalSince(target)) < 60 } ?? false
                    NavButton(label: name, large: true, tint: selected ? .orange : nil) { state.caffeineUntil = target }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
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
        return VStack(alignment: .leading, spacing: 10) {
            header {
                Text(stale ? "offline · \(relative(snap.lastUpdated, now: now)) ago"
                     : now.timeIntervalSince1970 - snap.lastUpdated < 2 * max(30, pollSeconds) ? "live" : "updated \(relative(snap.lastUpdated, now: now)) ago")
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
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .opacity(stale ? 0.6 : 1)
        .transition(.opacity)
    }

    /// Title row: sub-page pills when the tab has several pages, else the page title.
    private func header<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        let pages = state.page.tab.pages
        return HStack(spacing: 6) {
            if pages.count > 1, pages.contains(state.page) {
                ForEach(pages, id: \.self) { p in
                    NavButton(label: p.title, tint: state.page == p ? .white : nil) { setPage(p) }
                }
            } else {
                Text(state.page.title).font(.headline)
            }
            Spacer()
            trailing().font(.caption).foregroundStyle(.gray)
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
            header { EmptyView() }
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
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
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
        .frame(height: 70)
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
        return VStack(alignment: .leading, spacing: 8) {
            header {
                if let r = snap.weeklyResetsAt { Text("resets \(resetText(r, now: now))") }
            }
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
            .frame(height: 120)
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
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .transition(.opacity)
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
        .scaleEffect(hovered ? 1.08 : 1)
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .pointerStyle(.default)  // solid arrow; push/pop of NSCursor was overridden in the non-key panel
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
