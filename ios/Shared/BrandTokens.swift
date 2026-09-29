import SwiftUI

/// Token warna dan tipografi Rambu, dipakai app dan widget Live Activity.
/// Merah dan kuning hanya dipakai untuk tingkat risiko supaya maknanya tidak larut.
enum Brand {
    static let teal = Color(hex: 0x006F63)
    static let tealBright = Color(hex: 0x00937F)
    static let tealDeep = Color(hex: 0x054F47)
    static let tealSoft = Color(hex: 0xE2F2EF)

    static let ink = Color(hex: 0x0F2A29)
    static let ink2 = Color(hex: 0x3B5250)
    static let ink3 = Color(hex: 0x5B716F)
    static let canvas = Color(hex: 0xF2F6F5)
    static let hairline = Color(hex: 0xDCE7E4)

    static let signal = Color(hex: 0xE59A0C)
    static let signalSoft = Color(hex: 0xFEF2D6)
    static let signalInk = Color(hex: 0x6B4500)

    static let danger = Color(hex: 0xC0332A)
    static let dangerSoft = Color(hex: 0xFDE8E5)
    static let dangerInk = Color(hex: 0x9E1F15)

    static let safe = Color(hex: 0x1E8259)
    static let safeSoft = Color(hex: 0xE4F3EC)
    static let safeInk = Color(hex: 0x14603F)

    static let puckCream = Color(hex: 0xF4F0E6)
    static let puckCreamShade = Color(hex: 0xD9D1BE)

    static let hero = LinearGradient(
        colors: [Color(hex: 0x00937F), Color(hex: 0x006F63), Color(hex: 0x054F47)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Judul memakai SF Pro Rounded agar senada dengan maskot; isi tetap SF Pro.
    /// Keduanya mengikuti Dynamic Type karena berbasis text style.
    static func display(_ style: Font.TextStyle, _ weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Tiga tingkat risiko yang dilihat pengguna. Tingkat Aman tidak diteruskan ke pengawas.
enum RiskLevel: Int, Codable, Hashable, Comparable, CaseIterable, Sendable {
    case safe = 0
    case review = 1
    case danger = 2

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .safe: "Aman"
        case .review: "Perlu dicek"
        case .danger: "Bahaya"
        }
    }

    /// Label pendek untuk ruang sempit seperti Dynamic Island.
    var shortTitle: String {
        switch self {
        case .safe: "Aman"
        case .review: "Cek"
        case .danger: "Bahaya"
        }
    }

    /// Bentuk ikut membedakan tingkat: lingkaran, segitiga, oktagon.
    /// Status tetap terbaca tanpa warna.
    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .danger: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .safe: Brand.safe
        case .review: Brand.signal
        case .danger: Brand.danger
        }
    }

    var soft: Color {
        switch self {
        case .safe: Brand.safeSoft
        case .review: Brand.signalSoft
        case .danger: Brand.dangerSoft
        }
    }

    var ink: Color {
        switch self {
        case .safe: Brand.safeInk
        case .review: Brand.signalInk
        case .danger: Brand.dangerInk
        }
    }

    /// Warna tanda seru di dalam ikon. Kuning butuh tanda gelap supaya kontrasnya cukup.
    var glyph: Color {
        self == .review ? Brand.signalInk : .white
    }

    var parentAdvice: String {
        switch self {
        case .safe: "Belum ada tanda penipuan."
        case .review: "Jangan berikan data apa pun dulu."
        case .danger: "Jangan transfer. Jangan sebutkan kode apa pun."
        }
    }

    var relaysToGuardians: Bool { self != .safe }
}
