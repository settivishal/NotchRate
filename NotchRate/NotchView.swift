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
        return HStack(spacing: 0) {
            dot(level).frame(width: geo.hasNotch ? geo.wingWidth : 30)
            if geo.hasNotch { Color.clear.frame(width: geo.notchWidth) }
            pctText(snap.peakPct, level: level)
                .padding(.trailing, geo.hasNotch ? 14 : 0)  // stay clear of the bottom corner curve
                .frame(width: geo.hasNotch ? geo.wingWidth : nil, alignment: geo.hasNotch ? .center : .leading)
        }
        .frame(height: geo.topHeight)
        .opacity(level == .stale ? 0.5 : 1)
    }

    private func dot(_ level: Level) -> some View {
        Circle().fill(level.color).frame(width: 8, height: 8)
    }

    private func pctText(_ pct: Double, level: Level) -> some View {
        Text("\(Int(pct.rounded()))%")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(level == .stale ? .gray : .white)
    }

    // MARK: expanded

    private func expanded(_ snap: UsageSnapshot, level: Level, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: state.geometry.topHeight)  // physical notch region
            HStack {
                Text("Claude Code").font(.headline)
                Spacer()
                if level == .stale {
                    Text("stale · \(relative(snap.lastUpdated, now: now)) ago").font(.caption).foregroundStyle(.gray)
                }
            }
            bar("Session", snap.sessionUsedPct, resets: snap.sessionResetsAt, now: now)
            bar("Weekly", snap.weeklyUsedPct, resets: snap.weeklyResetsAt, now: now)
            HStack {
                Label(snap.costUsd.map { $0.formatted(.currency(code: "USD")) } ?? "—", systemImage: "dollarsign.circle")
                Spacer()
                Label("\(Int((snap.contextPct ?? 0).rounded()))% context", systemImage: "rectangle.stack")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .opacity(level == .stale ? 0.6 : 1)
        .transition(.opacity)
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
