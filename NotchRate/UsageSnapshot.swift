import SwiftUI

/// Normalized usage shape every adapter writes to ~/.notch-usage/<tool>.json.
struct UsageSnapshot: Codable, Equatable, Identifiable {
    var tool: String
    var sessionUsedPct: Double?
    var sessionResetsAt: Double?
    var weeklyUsedPct: Double?
    var weeklyResetsAt: Double?
    var costUsd: Double?
    var contextPct: Double?
    var lastUpdated: Double

    var id: String { tool }

    /// Highest of the rate-limit buckets; drives badge color.
    var peakPct: Double { max(sessionUsedPct ?? 0, weeklyUsedPct ?? 0) }

    func isStale(now: Date = .now, staleAfter: TimeInterval) -> Bool {
        now.timeIntervalSince1970 - lastUpdated > staleAfter
    }

    func level(now: Date = .now, staleAfter: TimeInterval) -> Level {
        isStale(now: now, staleAfter: staleAfter) ? .stale : Level(pct: peakPct)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

enum Level: Equatable {
    case green, yellow, red, stale

    init(pct: Double) {
        self = pct < 60 ? .green : pct < 85 ? .yellow : .red
    }

    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .stale: .gray
        }
    }
}
