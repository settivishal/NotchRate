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

    static func register() {
        UserDefaults.standard.register(defaults: [staleHours: 2.0, hoverDelay: 0.3, allDisplays: true, wingWidth: 44.0, showWeekly: false, hideBadge: false, ringGauges: true, pollSeconds: 60.0, cardRadius: 28.0])
    }
    static var staleAfter: TimeInterval { UserDefaults.standard.double(forKey: staleHours) * 3600 }
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Toggle("Hide badge (menu bar only)", isOn: $hideBadge)
            Toggle("Show weekly (7d) in badge", isOn: $showWeekly)
            Picker("Expanded gauges", selection: $ringGauges) {
                Text("Rings").tag(true)
                Text("Bars").tag(false)
            }
            .pickerStyle(.segmented)
            Toggle("Follow mouse to every display (pill on plain displays)", isOn: $allDisplays)
            Slider(value: $hoverDelay, in: 0...1, step: 0.05) {
                Text("Hover delay: \(hoverDelay, format: .number.precision(.fractionLength(2)))s")
            }
            Slider(value: $wingWidth, in: 30...120, step: 2) {
                Text("Badge width beside notch: \(Int(wingWidth))pt")
            }
            Slider(value: $cardRadius, in: 8...48, step: 2) {
                Text("Card corner radius: \(Int(cardRadius))pt")
            } onEditingChanged: { AppDelegate.shared?.preview($0) }
            Slider(value: $pollSeconds, in: 30...600, step: 30) {
                Text("Poll usage every \(Int(pollSeconds))s")
            }
            Slider(value: $staleHours, in: 0.5...12, step: 0.5) {
                Text("Mark offline after \(staleHours, format: .number.precision(.fractionLength(1)))h without updates")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
