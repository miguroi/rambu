import SwiftUI

// MARK: - Orang dan peran

/// Peran yang sedang dilihat. Di produk nyata satu HP adalah satu orang;
/// mode demo menggabungkan ketiganya di satu HP.
enum Persona: String, CaseIterable, Identifiable, Codable, Sendable {
    case ratna, sinta, richard

    var id: String { rawValue }

    /// Data contoh sebelum nama diisi saat onboarding. Nama sebenarnya ada di AppModel.
    var defaultPerson: Person {
        switch self {
        case .ratna: .ratna
        case .sinta: .sinta
        case .richard: .richard
        }
    }

    var isParent: Bool { self == .ratna }
    var roleLabel: String { isParent ? "Orang tua" : "Pengawas" }
}

struct Person: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let initial: String
    let relation: String
    let colorHex: UInt32

    var color: Color { Color(hex: colorHex) }
}

extension Person {
    static let ratna = Person(id: "ratna", name: "Ibu Ratna", initial: "R", relation: "Ibu", colorHex: 0x006F63)
    static let sinta = Person(id: "sinta", name: "Sinta", initial: "S", relation: "Anak", colorHex: 0x1E6E9E)
    static let richard = Person(id: "richard", name: "Richard", initial: "R", relation: "Anak", colorHex: 0x6347A8)
    static let guardians: [Person] = [.sinta, .richard]

    /// Nama baru dengan warna dan id yang sama. Inisial diambil dari kata terakhir,
    /// jadi "Ibu Ratna" menjadi R, bukan I.
    func renamed(_ newName: String, relation newRelation: String? = nil) -> Person {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? self.name : trimmed
        let initial = name.split(separator: " ").last?.first.map { String($0).uppercased() } ?? self.initial
        return Person(id: id, name: name, initial: initial, relation: newRelation ?? relation, colorHex: colorHex)
    }
}

// MARK: - Tanda penipuan

/// Kategori tanda social engineering yang dicari di percakapan.
enum SignalKind: String, Codable, CaseIterable, Hashable, Sendable {
    case impersonation, urgency, secretCode, transfer, remoteApp

    /// Nama kategori untuk pengawas.
    var title: String {
        switch self {
        case .impersonation: "Mengaku dari lembaga"
        case .urgency: "Desakan waktu"
        case .secretCode: "Meminta kode OTP atau PIN"
        case .transfer: "Meminta transfer uang"
        case .remoteApp: "Menyuruh pasang aplikasi"
        }
    }

    /// Kalimat pendek untuk orang tua saat telepon masih berjalan.
    var parentHeadline: String {
        switch self {
        case .impersonation: "Penelepon mengaku dari lembaga"
        case .urgency: "Penelepon mendesak Anda"
        case .secretCode: "Penelepon meminta kode rahasia"
        case .transfer: "Penelepon meminta transfer"
        case .remoteApp: "Penelepon menyuruh pasang aplikasi"
        }
    }

    var symbol: String {
        switch self {
        case .impersonation: "building.columns.fill"
        case .urgency: "timer"
        case .secretCode: "key.fill"
        case .transfer: "banknote.fill"
        case .remoteApp: "arrow.down.app.fill"
        }
    }

    /// Tingkat minimum yang ditandai sinyal ini jika muncul sendirian.
    var floor: RiskLevel {
        switch self {
        case .impersonation, .urgency: .review
        case .secretCode, .transfer, .remoteApp: .danger
        }
    }
}

/// Aturan penilaian tiruan untuk prototipe. Backend menggantinya dengan analisis Langflow.
enum RiskRules {
    static func level(for signals: Set<SignalKind>) -> RiskLevel {
        if signals.isEmpty { return .safe }
        if signals.count >= 2 { return .danger }
        return signals.map(\.floor).max() ?? .safe
    }
}

// MARK: - Panggilan

enum CallChannel: String, Codable, Hashable, Sendable {
    case cellular, whatsapp

    var label: String { self == .cellular ? "Telepon seluler" : "Panggilan WhatsApp" }
    var short: String { self == .cellular ? "Telepon" : "WhatsApp" }
    var symbol: String { self == .cellular ? "phone.fill" : "bubble.left.fill" }
}

enum Speaker: String, Codable, Hashable, Sendable {
    case caller, parent

    var label: String { self == .caller ? "Penelepon" : "Orang tua" }
}

/// Satu potongan transkrip ±5 detik.
struct TranscriptLine: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let offset: TimeInterval
    let speaker: Speaker
    let text: String
    let flagged: [String]
    let signals: [SignalKind]

    var isFlagged: Bool { !signals.isEmpty }
}

struct Scenario: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let callerName: String
    let callerDetail: String
    let channel: CallChannel
    let lines: [TranscriptLine]

    var expectedLevel: RiskLevel { RiskRules.level(for: Set(lines.flatMap(\.signals))) }
}

/// Panggilan yang sedang berlangsung di HP orang tua.
struct CallSession: Identifiable, Sendable {
    let id: UUID
    let scenario: Scenario
    let startedAt: Date
    var heard: [TranscriptLine] = []
    var signals: [SignalKind] = []
    var level: RiskLevel = .safe
    var isListening = true
    /// Puck hanya mendengar dari loudspeaker. Kalau mati, Rambu belum bisa menilai apa pun.
    var speakerOn = true

    var headline: String { signals.last?.parentHeadline ?? "Rambu mendengarkan" }
}

// MARK: - Keputusan keluarga

enum Verdict: String, Codable, Hashable, Sendable {
    case scam, safe

    var buttonTitle: String { self == .scam ? "Ini penipuan" : "Aman" }
    var pastTitle: String { self == .scam ? "penipuan" : "aman" }
}

struct GuardianDecision: Hashable, Codable, Sendable {
    let by: Person
    let verdict: Verdict
    let at: Date
}

enum DecisionOutcome: Equatable, Sendable {
    case accepted(GuardianDecision)
    case alreadyDecided(GuardianDecision)
    case unknownAlert
}

/// Peringatan yang dikirim ke semua pengawas. Hanya kalimat penelepon yang memicu
/// peringatan yang ikut terkirim; percakapan lengkap tetap di HP orang tua.
struct FamilyAlert: Identifiable, Hashable, Sendable {
    let id: UUID
    let parent: Person
    let callerDetail: String
    let channel: CallChannel
    let startedAt: Date
    var raisedAt: Date
    var level: RiskLevel
    var signals: [SignalKind]
    var evidence: [TranscriptLine]
    var recipients: [Person]
    var decision: GuardianDecision?
    var callEnded = false

    var title: String {
        level == .danger ? "\(parent.name) mungkin sedang ditipu" : "Telepon \(parent.name) mencurigakan"
    }
}

struct CallRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let callerDetail: String
    let channel: CallChannel
    let startedAt: Date
    let duration: TimeInterval
    var level: RiskLevel
    var signals: [SignalKind]
    var evidence: [TranscriptLine]
    var decision: GuardianDecision?
}

// MARK: - Puck

struct PuckState: Hashable, Codable, Sendable {
    var isPaired: Bool
    var isConnected: Bool
    var battery: Int
    var isCharging: Bool
    var name: String
    var serial: String
    var firmware: String

    var batterySymbol: String {
        if isCharging { return "battery.100percent.bolt" }
        switch battery {
        case 76...: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    static let demo = PuckState(isPaired: true, isConnected: true, battery: 82, isCharging: false,
                                name: "Rambu Puck", serial: "RP-2F8A", firmware: "0.3.1")
    static let unpaired = PuckState(isPaired: false, isConnected: false, battery: 0, isCharging: false,
                                    name: "Rambu Puck", serial: "", firmware: "")
}

// MARK: - Navigasi

enum ParentTab: Hashable { case home, history, puck }
enum GuardianTab: Hashable { case home, history }

enum OnboardingStep: String, Hashable, Sendable {
    // Jalur orang tua
    case welcome, tutorial, parentProfile, pairPuck, consent, invite, practiceCall
    // Jalur pengawas
    case enterCode, guardianProfile, practiceAlert, waiting
}

// MARK: - Gangguan

/// Hal yang membuat Rambu tidak bisa bekerja penuh. Tampil sebagai banner di beranda.
enum SystemIssue: String, Identifiable, CaseIterable, Sendable {
    case notificationsOff, offline, bluetoothOff, puckDisconnected, puckLowBattery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notificationsOff: "Notifikasi mati"
        case .offline: "Tidak ada internet"
        case .bluetoothOff: "Bluetooth mati"
        case .puckDisconnected: "Puck terputus"
        case .puckLowBattery: "Baterai puck lemah"
        }
    }

    var detail: String {
        switch self {
        case .notificationsOff: "Peringatan tidak akan muncul."
        case .offline: "Pengawas belum bisa dikabari."
        case .bluetoothOff: "Rambu tidak bisa mendengar."
        case .puckDisconnected: "Dekatkan puck ke HP."
        case .puckLowBattery: "Isi daya sebelum habis."
        }
    }

    var symbol: String {
        switch self {
        case .notificationsOff: "bell.slash.fill"
        case .offline: "wifi.slash"
        case .bluetoothOff: "antenna.radiowaves.left.and.right.slash"
        case .puckDisconnected: "circle.slash"
        case .puckLowBattery: "battery.25percent"
        }
    }

    /// Label tombol, kalau masalahnya bisa dibereskan dari sini.
    var action: String? {
        switch self {
        case .notificationsOff: "Nyalakan"
        case .bluetoothOff: "Pengaturan"
        case .puckDisconnected: "Sambungkan"
        case .offline, .puckLowBattery: nil
        }
    }
}

/// Isi push Rambu. Dikirim sebagai notifikasi sistem, atau tampil sebagai tiruan banner
/// di dalam app kalau izin notifikasi belum ada.
struct Toast: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    /// Menentukan warna dan papan yang dipegang maskot.
    let level: RiskLevel
    let alertID: UUID?
}

// MARK: - Format tanggal berbahasa Indonesia

enum Fmt {
    static let locale = Locale(identifier: "id_ID")

    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar(identifier: .gregorian)
        if calendar.isDate(date, inSameDayAs: now) { return "Hari ini, \(clock(date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Kemarin, \(clock(date))"
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 { return "\(rest) dtk" }
        return rest == 0 ? "\(minutes) mnt" : "\(minutes) mnt \(rest) dtk"
    }

    static func offset(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Ringkasan kejadian

extension CallRecord {
    /// Ringkasan singkat untuk riwayat. Di produk nyata teks ini dibuat backend
    /// (watsonx Orchestrate) dari transkrip dan keputusan. Prototipe menyusunnya dari data yang sama.
    var incidentSummary: String {
        let actions = signals.map(\.summaryPhrase)
        let listed = actions.formatted(.list(type: .and).locale(Fmt.locale))
        let what = actions.isEmpty ? "Tidak ada tanda penipuan." : "Penelepon \(listed)."
        let outcome: String
        if let decision {
            outcome = decision.verdict == .scam
                ? "\(decision.by.name) menandai penipuan pukul \(Fmt.clock(decision.at))."
                : "\(decision.by.name) menandai aman pukul \(Fmt.clock(decision.at))."
        } else {
            outcome = "Belum ada pengawas yang menjawab."
        }
        return "\(channel.label) \(Fmt.duration(duration)) dari \(callerDetail). \(what) \(outcome)"
    }
}

extension SignalKind {
    /// Frasa kerja untuk kalimat ringkasan, misalnya "Penelepon mengaku dari lembaga".
    var summaryPhrase: String {
        switch self {
        case .impersonation: "mengaku dari lembaga"
        case .urgency: "mendesak"
        case .secretCode: "meminta kode OTP atau PIN"
        case .transfer: "meminta transfer uang"
        case .remoteApp: "menyuruh pasang aplikasi"
        }
    }
}
