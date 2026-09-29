import ActivityKit
import Foundation

/// Live Activity saat orang tua sedang menelepon. Tampil di Lock Screen dan Dynamic Island,
/// sehingga status Rambu tetap terlihat di atas layar telepon bawaan iPhone.
struct RambuCallAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var level: RiskLevel
        var headline: String
        var isListening: Bool
        var decidedBy: String?
        var decisionIsScam: Bool?
    }

    var parentName: String
    var channel: String
    var startedAt: Date
}

extension RambuCallAttributes.ContentState {
    var decisionTitle: String? {
        guard let decidedBy, let decisionIsScam else { return nil }
        return decisionIsScam ? "\(decidedBy): ini penipuan" : "\(decidedBy): aman"
    }

    var decisionAdvice: String? {
        guard let decisionIsScam else { return nil }
        return decisionIsScam
            ? "Tutup telepon sekarang."
            : "Tetap jangan beri kode atau transfer."
    }
}
