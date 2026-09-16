import ServiceManagement
import SwiftUI

enum Pref {
    static let staleHours = "staleHours"       // Double, default 2
    static let hoverDelay = "hoverDelay"       // Double seconds, default 0.3
    static let allDisplays = "allDisplays"     // Bool, default true
    static let wingWidth = "wingWidth"         // Double points, default 44
    static let showWeekly = "showWeekly"       // Bool, default false: collapsed badge shows 5h and 7d
    static let hideBadge = "hideBadge"         // Bool, default false: menu bar item only
    static let ringGauges = "ringGauges"       // Bool, default true: expanded view uses rings, else bars
    static let pollSeconds = "pollSeconds"     // Double, default 60: OAuth usage poll interval
    static let cardRadius = "cardRadius"       // Double points, default 28: expanded card corner radius
    static let badgeCountdown = "badgeCountdown" // Bool, default false: badge shows time to reset instead of %
    static let badgeRing = "badgeRing"         // Bool, default false: tiny arc instead of the dot
    static let menuBarText = "menuBarText"     // Bool, default false: menu bar shows "5h 42%" instead of icon
    static let warnPct = "warnPct"             // Double, default 85: first notification threshold
    static let fullPct = "fullPct"             // Double, default 100: second notification threshold
    static let paceWarn = "paceWarn"           // Bool, default true: warn when pace hits 100% before reset
    static let hotkey = "hotkey"               // Bool, default true: ⌃⌥N toggles the card
    static let planNotify = "planNotify"       // Bool, default true: notify when Claude Code presents a plan
    static let approvals = "approvals"         // Bool, default true: Allow/Deny island for permission prompts
    static let paceWarnedFor = "paceWarnedFor" // Double: session resets_at already warned about

    static func register() {
        UserDefaults.standard.register(defaults: [
            staleHours: 2.0, hoverDelay: 0.3, allDisplays: true, wingWidth: 44.0, showWeekly: false, hideBadge: false,
            ringGauges: true, pollSeconds: 60.0, cardRadius: 28.0, badgeCountdown: false, badgeRing: false,
            menuBarText: false, warnPct: 85.0, fullPct: 100.0, paceWarn: true, hotkey: true, planNotify: true, approvals: true,
        ])
    }
    static var staleAfter: TimeInterval { UserDefaults.standard.double(forKey: staleHours) * 3600 }
    static var thresholds: [Double] { [UserDefaults.standard.double(forKey: warnPct), UserDefaults.standard.double(forKey: fullPct)] }
}

struct SettingsView: View {
    @AppStorage(Pref.staleHours) private var staleHours = 2.0
    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.3
    @AppStorage(Pref.allDisplays) private var allDisplays = true
    @AppStorage(Pref.wingWidth) private var wingWidth = 44.0
    @AppStorage(Pref.showWeekly) private var showWeekly = false
    @AppStorage(Pref.hideBadge) private var hideBadge = false
    @AppStorage(Pref.ringGauges) private var ringGauges = true
    @AppStorage(Pref.pollSeconds) private var pollSeconds = 60.0
    @AppStorage(Pref.cardRadius) private var cardRadius = 28.0
    @AppStorage(Pref.badgeCountdown) private var badgeCountdown = false
    @AppStorage(Pref.badgeRing) private var badgeRing = false
    @AppStorage(Pref.menuBarText) private var menuBarText = false
    @AppStorage(Pref.warnPct) private var warnPct = 85.0
    @AppStorage(Pref.fullPct) private var fullPct = 100.0
    @AppStorage(Pref.paceWarn) private var paceWarn = true
    @AppStorage(Pref.hotkey) private var hotkey = true
    @AppStorage(Pref.planNotify) private var planNotify = true
    @AppStorage(Pref.approvals) private var approvals = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Toggle("Global hotkey ⌃⌥N toggles the card", isOn: $hotkey)
                Toggle("Show usage text in the menu bar", isOn: $menuBarText)
                Slider(value: $pollSeconds, in: 30...600, step: 30) { Text("Poll usage every \(Int(pollSeconds))s") }
                Slider(value: $staleHours, in: 0.5...12, step: 0.5) {
                    Text("Mark offline after \(staleHours, format: .number.precision(.fractionLength(1)))h without updates")
                }
            }
            Section("Badge") {
                Toggle("Hide badge (menu bar only)", isOn: $hideBadge)
                Toggle("Show weekly (7d) in badge", isOn: $showWeekly)
                Toggle("Time to reset instead of %", isOn: $badgeCountdown)
                Toggle("Ring instead of dot", isOn: $badgeRing)
                Toggle("Follow mouse to every display (pill on plain displays)", isOn: $allDisplays)
                Slider(value: $wingWidth, in: 30...120, step: 2) { Text("Badge width beside notch: \(Int(wingWidth))pt") }
            }
            Section("Card") {
                Picker("Gauges", selection: $ringGauges) {
                    Text("Rings").tag(true)
                    Text("Bars").tag(false)
                }
                .pickerStyle(.segmented)
                Slider(value: $hoverDelay, in: 0...1, step: 0.05) {
                    Text("Hover delay: \(hoverDelay, format: .number.precision(.fractionLength(2)))s")
                }
                Slider(value: $cardRadius, in: 8...48, step: 2) {
                    Text("Corner radius: \(Int(cardRadius))pt")
                } onEditingChanged: { AppDelegate.shared?.preview($0) }
            }
            Section("Alerts") {
                Slider(value: $warnPct, in: 50...99, step: 1) { Text("Warn at \(Int(warnPct))%") }
                Slider(value: $fullPct, in: 60...100, step: 1) { Text("Alert at \(Int(fullPct))%") }
                Toggle("Warn when pace hits 100% before reset", isOn: $paceWarn)
            }
            Section("Claude Code") {
                Toggle("Allow/Deny island for permission prompts", isOn: $approvals)
                Text("Answer on the notch within \(Int(Approvals.wait))s, or in the terminal as usual.").font(.caption).foregroundStyle(.secondary)
                Toggle("Notify when a plan is ready for review", isOn: $planNotify)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 740)
    }
}
