import SwiftUI

@MainActor
@Observable
final class NotchState {
    var geometry: NotchGeometry
    var expanded = false
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

struct NotchView: View {
    let store: UsageStore
    let state: NotchState
    var setExpanded: (Bool) -> Void

    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.3
    @AppStorage(Pref.staleHours) private var staleHours = 2.0
    @AppStorage(Pref.showWeekly) private var showWeekly = false
    @AppStorage(Pref.ringGauges) private var ringGauges = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTask: Task<Void, Never>?

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.8)
    }

    var body: some View {
        let geo = state.geometry
        let size = state.expanded ? geo.expandedSize : geo.collapsedSize
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            ZStack(alignment: .top) {
                NotchShape(topRadius: geo.hasNotch ? 6 : 0, bottomRadius: state.expanded ? 20 : 12)
                    .fill(.black)
                if let snap = store.primary {
                    let level = snap.level(now: ctx.date, staleAfter: staleHours * 3600)
                    if state.expanded {
                        expanded(snap, level: level, now: ctx.date)
                    } else {
                        collapsed(snap, level: level)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .animation(animation, value: state.expanded)
            .onHover(perform: hover)
            .onTapGesture { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(hoverDelay))
                guard !Task.isCancelled else { return }
                setExpanded(true)
            }
        } else {
            setExpanded(false)
        }
    }

    // MARK: collapsed

    private func collapsed(_ snap: UsageSnapshot, level: Level) -> some View {
        let geo = state.geometry
        let stale = level == .stale
        let session = stale ? .stale : Level(pct: snap.sessionUsedPct ?? 0)
        let weekly = stale ? .stale : Level(pct: snap.weeklyUsedPct ?? 0)
        // 14pt pads keep text clear of the bottom corner curves.
        return HStack(spacing: 0) {
            Group {
                if showWeekly {
                    bucket("5h", snap.sessionUsedPct, level: session).padding(.leading, geo.hasNotch ? 14 : 0)
                } else {
                    Circle().fill(session.color).frame(width: 8, height: 8)
                }
            }
            .frame(width: geo.hasNotch ? geo.wingWidth : 30)
            if geo.hasNotch { Color.clear.frame(width: geo.notchWidth) }
            Group {
                if showWeekly {
                    bucket("7d", snap.weeklyUsedPct, level: weekly)
                } else {
                    pctText(snap.sessionUsedPct, stale: stale)
                }
            }
            .padding(.trailing, geo.hasNotch ? 14 : 0)
            .frame(width: geo.hasNotch ? geo.wingWidth : nil, alignment: geo.hasNotch ? .center : .leading)
        }
        .frame(height: geo.topHeight)
        .opacity(stale ? 0.5 : 1)
    }

    /// Caption carries the color so no dot is needed.
    private func bucket(_ label: String, _ pct: Double?, level: Level) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(level.color)
            pctText(pct, stale: level == .stale)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }

    private func pctText(_ pct: Double?, stale: Bool) -> some View {
        Text(pct.map { "\(Int($0.rounded()))%" } ?? "—")
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
            Color.clear.frame(height: state.geometry.topHeight)  // physical notch region
            HStack {
                Text("Claude").font(.headline)
                Spacer()
                Text("\(stale ? "stale" : "updated") · \(relative(snap.lastUpdated, now: now)) ago")
                    .font(.caption).foregroundStyle(.gray)
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
            Divider().overlay(.white.opacity(0.15))
            HStack {
                Text(snap.costUsd.map { $0.formatted(.currency(code: "USD")) + " spent" } ?? "—")
                Spacer()
                Text("\(Int((snap.contextPct ?? 0).rounded()))% context")
                Spacer()
                Label("usage", systemImage: "arrow.up.right").labelStyle(.titleAndIcon)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .opacity(stale ? 0.6 : 1)
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

    private func relative(_ epoch: Double, now: Date) -> String {
        let secs = Int(abs(now.timeIntervalSince1970 - epoch))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
