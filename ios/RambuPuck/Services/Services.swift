@preconcurrency import ActivityKit
import Foundation

// MARK: - Batas serah terima ke backend
//
// Tiga protokol di bawah adalah satu-satunya titik yang perlu diganti tim backend.
// UI hanya bergantung pada protokol ini, bukan pada implementasi simulasinya.
// Lihat ios/README.md untuk kontrak lengkapnya.

/// Identitas panggilan yang sedang diperiksa.
struct CallContext: Sendable {
    let id: UUID
    let metadata: CallMetadata
    let startedAt: Date
}

/// Hasil pemeriksaan satu potongan audio ±5 detik dari puck.
struct ChunkAssessment: Sendable {
    let line: TranscriptLine
    /// Tingkat keseluruhan panggilan setelah potongan ini. Tidak pernah turun.
    let level: RiskLevel
    /// Tanda yang terdeteksi di potongan ini saja.
    let signals: [SignalKind]
}

/// Sumber penilaian risiko selama panggilan.
/// Nyata: audio puck → POST /transcribe (backend/) → analisis Langflow → ChunkAssessment.
protocol CallAnalysisSession: Sendable {
    var assessments: AsyncThrowingStream<ChunkAssessment, Error> { get }
    var statusUpdates: AsyncStream<ProtectionStatus> { get }
    func finish() async throws
    func cancel() async throws
}

protocol CallAnalysisSource: Sendable {
    var usesAuthoritativeRemoteAlerts: Bool { get }
    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error>
    func start(for call: CallContext) async throws -> any CallAnalysisSession
}

extension CallAnalysisSource {
    var usesAuthoritativeRemoteAlerts: Bool { false }

    func start(for call: CallContext) async throws -> any CallAnalysisSession {
        LegacyCallAnalysisSession(assessments: assessments(for: call))
    }
}

private struct LegacyCallAnalysisSession: CallAnalysisSession {
    let assessments: AsyncThrowingStream<ChunkAssessment, Error>
    let statusUpdates = AsyncStream<ProtectionStatus> { $0.finish() }

    func finish() async throws {}
    func cancel() async throws {}
}

/// Saluran keluarga: menyebarkan peringatan ke semua pengawas dan menerima keputusan.
/// Server nyata wajib menegakkan aturan "keputusan pertama yang berlaku".
@MainActor
protocol FamilyRelay: AnyObject {
    var onEvent: ((RelayEvent) -> Void)? { get set }
    func publish(_ alert: FamilyAlert)
    func submit(_ decision: GuardianDecision, for alertID: UUID) -> DecisionOutcome
}

enum RelayEvent: Sendable {
    case alert(FamilyAlert)
    case decided(alertID: UUID, GuardianDecision)
}

/// Koneksi Bluetooth ke Rambu Puck.
/// Nyata: CoreBluetooth, menunggu spesifikasi GATT dari tim hardware.
@MainActor
protocol PuckLink: AnyObject {
    func discover() async -> PuckState
}

/// Relay di memori. Menjalankan aturan yang sama dengan server nyata:
/// keputusan pertama yang masuk berlaku, keputusan berikutnya ditolak.
@MainActor
final class LocalFamilyRelay: FamilyRelay {
    var onEvent: ((RelayEvent) -> Void)?
    private var alerts: [UUID: FamilyAlert] = [:]

    func publish(_ alert: FamilyAlert) {
        var stored = alert
        // Pembaruan tingkat risiko tidak boleh menghapus keputusan yang sudah masuk.
        stored.decision = alerts[alert.id]?.decision
        alerts[alert.id] = stored
        onEvent?(.alert(stored))
    }

    func submit(_ decision: GuardianDecision, for alertID: UUID) -> DecisionOutcome {
        guard var alert = alerts[alertID] else { return .unknownAlert }
        if let existing = alert.decision { return .alreadyDecided(existing) }
        alert.decision = decision
        alerts[alertID] = alert
        onEvent?(.decided(alertID: alertID, decision))
        return .accepted(decision)
    }
}

@MainActor
final class SimulatedPuckLink: PuckLink {
    func discover() async -> PuckState {
        try? await Task.sleep(for: .seconds(2))
        return .demo
    }
}

// MARK: - Live Activity

/// Mengatur Live Activity panggilan. Bersifat pelengkap: kalau Live Activity
/// dimatikan pengguna, layar di dalam app tetap berjalan normal.
@MainActor
final class CallLiveActivity {
    private var activity: Activity<RambuCallAttributes>?
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
        guard enabled else { return }
        // Live Activity dari proses sebelumnya (misal app ditutup paksa saat menelepon)
        // tidak ikut berakhir. Daftarnya diambil sekarang supaya yang dibuat sesudah ini aman.
        let stale = Activity<RambuCallAttributes>.activities
        if !stale.isEmpty {
            Task {
                for activity in stale {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    var isActive: Bool { activity != nil }

    func start(attributes: RambuCallAttributes, state: RambuCallAttributes.ContentState) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(state: state, dismissImmediately: true)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(_ state: RambuCallAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(state: RambuCallAttributes.ContentState, dismissImmediately: Bool = false) {
        guard let activity else { return }
        self.activity = nil
        let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .after(.now.addingTimeInterval(10))
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
}
