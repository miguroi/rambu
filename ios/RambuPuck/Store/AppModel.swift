import SwiftUI
import Observation

/// Satu sumber kebenaran untuk seluruh app.
/// Di demo, ketiga peran (Ibu Ratna, Sinta, Richard) berbagi model yang sama
/// sehingga peringatan dan keputusan langsung terlihat saat berganti peran.
@MainActor
@Observable
final class AppModel {
    var persona: Persona
    var onboardingComplete: Bool
    var onboardingStep: OnboardingStep = .welcome
    var puck: PuckState

    /// Diisi saat onboarding. Nilai awalnya data contoh supaya demo langsung jalan.
    var parent: Person = .ratna
    var guardians: [Person] = Person.guardians

    var session: CallSession?
    var isCallScreenPresented = false
    var alerts: [FamilyAlert] = []
    var history: [CallRecord]

    var parentTab: ParentTab = .home
    var guardianTab: GuardianTab = .home
    var guardianPath: [UUID] = []
    var showDemoSheet = false
    var toast: Toast?

    @ObservationIgnored private let analysis: any CallAnalysisSource
    @ObservationIgnored private let relay: any FamilyRelay
    @ObservationIgnored private let liveActivity: CallLiveActivity
    @ObservationIgnored private let notifier: RambuNotifier
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    init(
        persona: Persona = .ratna,
        onboardingComplete: Bool = false,
        analysis: any CallAnalysisSource = ScenarioAnalysis(),
        relay: (any FamilyRelay)? = nil,
        liveActivities: Bool = true,
        notifications: Bool = true,
        now: Date = .now
    ) {
        self.persona = persona
        self.onboardingComplete = onboardingComplete
        self.puck = onboardingComplete ? .demo : .unpaired
        self.history = CallRecord.seed(now: now)
        self.analysis = analysis
        self.relay = relay ?? LocalFamilyRelay()
        self.liveActivity = CallLiveActivity(enabled: liveActivities)
        self.notifier = RambuNotifier(enabled: notifications)
        self.relay.onEvent = { [weak self] event in self?.handle(event) }
        self.notifier.onOpen = { [weak self] id in self?.openFromPush(id) }
    }

    var currentPerson: Person { person(for: persona) }

    /// Orang yang diwakili sebuah peran demo, memakai nama yang diisi saat onboarding.
    func person(for persona: Persona) -> Person {
        switch persona {
        case .ratna: parent
        case .sinta: guardians.first ?? .sinta
        case .richard: guardians.dropFirst().first ?? .richard
        }
    }

    func renameParent(_ name: String) {
        parent = parent.renamed(name)
    }

    func renameGuardian(_ persona: Persona, name: String, relation: String) {
        let index = persona == .richard ? 1 : 0
        guard guardians.indices.contains(index) else { return }
        guardians[index] = guardians[index].renamed(name, relation: relation)
    }

    /// Peringatan untuk panggilan yang sedang berjalan.
    var activeAlert: FamilyAlert? {
        guard let id = session?.id else { return nil }
        return alerts.first { $0.id == id }
    }

    /// Peringatan terbaru yang layak ditonjolkan di beranda pengawas.
    var featuredAlert: FamilyAlert? {
        alerts.first { $0.decision == nil } ?? alerts.first { !$0.callEnded }
    }

    func otherGuardians(than person: Person) -> [Person] {
        guardians.filter { $0 != person }
    }

    // MARK: Push

    func requestNotifications() async {
        await notifier.requestAuthorization()
    }

    /// Push sistem kalau diizinkan, tiruan banner di dalam app kalau belum.
    private func present(_ push: Toast) {
        if notifier.isAuthorized {
            notifier.post(push)
        } else {
            toast = push
        }
    }

    private func openFromPush(_ id: UUID?) {
        toast = nil
        guard !persona.isParent, let id else { return }
        openAlert(id)
    }

    private var guardianNames: String {
        guardians.map(\.name).formatted(.list(type: .and).locale(Fmt.locale))
    }

    private func parentWarning(for session: CallSession) -> Toast {
        let danger = session.level == .danger
        return Toast(
            id: "\(session.id)-\(session.level.rawValue)",
            title: danger ? "Bahaya: terindikasi penipuan" : "Waspada: telepon mencurigakan",
            body: danger
                ? "Hati-hati. Jangan transfer atau sebut kode. Sudah dikirim ke \(guardianNames)."
                : "\(session.headline). Jangan beri data dulu. Sudah dikirim ke \(guardianNames).",
            level: session.level,
            alertID: session.id
        )
    }

    // MARK: Onboarding & demo

    func completeOnboarding(as persona: Persona) {
        self.persona = persona
        puck = .demo
        history = CallRecord.seed(decider: person(for: .richard))
        onboardingComplete = true
        onboardingStep = .welcome
    }

    func switchPersona(_ persona: Persona) {
        self.persona = persona
        guardianPath = []
        toast = nil
        if persona.isParent, session != nil { isCallScreenPresented = true }
    }

    func resetDemo() {
        listenTask?.cancel()
        listenTask = nil
        if let session { liveActivity.end(state: activityState(for: session), dismissImmediately: true) }
        session = nil
        isCallScreenPresented = false
        alerts = []
        history = CallRecord.seed()
        toast = nil
        guardianPath = []
        parentTab = .home
        guardianTab = .home
        persona = .ratna
        parent = .ratna
        guardians = Person.guardians
        puck = .unpaired
        onboardingComplete = false
        onboardingStep = .welcome
    }

    // MARK: Orang tua

    /// Memulai panggilan simulasi. Mengembalikan task pendengar supaya tes bisa menunggunya.
    @discardableResult
    func startCall(_ template: Scenario) -> Task<Void, Never> {
        let scenario = template.personalized(parentName: parent.name)
        listenTask?.cancel()
        if let old = session { liveActivity.end(state: activityState(for: old), dismissImmediately: true) }

        let session = CallSession(id: UUID(), scenario: scenario, startedAt: .now)
        self.session = session
        persona = .ratna
        toast = nil
        isCallScreenPresented = true
        // Telepon yang aman tidak memunculkan apa pun. Live Activity dan push baru muncul
        // begitu ada tanda penipuan (lihat ingest).

        let context = CallContext(id: session.id, channel: scenario.channel, startedAt: session.startedAt, scenario: scenario)
        let stream = analysis.assessments(for: context)
        let sessionID = session.id
        let task = Task { [weak self] in
            for await chunk in stream {
                self?.ingest(chunk, sessionID: sessionID)
            }
        }
        listenTask = task
        return task
    }

    private func ingest(_ chunk: ChunkAssessment, sessionID: UUID) {
        guard var current = session, current.id == sessionID else { return }
        let previous = current.level

        current.heard.append(chunk.line)
        for signal in chunk.signals where !current.signals.contains(signal) {
            current.signals.append(signal)
        }
        // Tingkat risiko tidak pernah turun dalam satu panggilan.
        current.level = max(current.level, chunk.level)
        session = current

        guard current.level.relaysToGuardians else { return }

        if liveActivity.isActive {
            liveActivity.update(activityState(for: current))
        } else {
            liveActivity.start(
                attributes: RambuCallAttributes(parentName: parent.name, channel: current.scenario.channel.short,
                                                startedAt: current.startedAt),
                state: activityState(for: current)
            )
        }

        if current.level > previous || chunk.line.isFlagged {
            relay.publish(makeAlert(from: current))
        }
        if current.level > previous, persona.isParent {
            present(parentWarning(for: current))
        }
    }

    private func makeAlert(from session: CallSession) -> FamilyAlert {
        let existing = alerts.first { $0.id == session.id }
        return FamilyAlert(
            id: session.id,
            parent: parent,
            callerDetail: session.scenario.callerDetail,
            channel: session.scenario.channel,
            startedAt: session.startedAt,
            raisedAt: existing?.raisedAt ?? .now,
            level: session.level,
            signals: session.signals,
            evidence: session.heard.filter { $0.speaker == .caller && $0.isFlagged },
            recipients: guardians,
            decision: existing?.decision
        )
    }

    func endCall() {
        guard let session else { return }
        listenTask?.cancel()
        listenTask = nil

        let alert = alerts.first { $0.id == session.id }
        // Riwayat hanya menyimpan telepon Waspada dan Bahaya.
        if session.level > .safe {
            let record = CallRecord(
                id: session.id,
                title: session.scenario.title,
                callerDetail: session.scenario.callerDetail,
                channel: session.scenario.channel,
                startedAt: session.startedAt,
                duration: Date.now.timeIntervalSince(session.startedAt),
                level: session.level,
                signals: session.signals,
                evidence: session.heard.filter { $0.speaker == .caller && $0.isFlagged },
                decision: alert?.decision
            )
            history.insert(record, at: 0)
        }
        if let index = alerts.firstIndex(where: { $0.id == session.id }) {
            alerts[index].callEnded = true
        }

        var final = activityState(for: session)
        final.isListening = false
        liveActivity.end(state: final)

        self.session = nil
        isCallScreenPresented = false
    }

    // MARK: Pengawas

    func canDecide(_ alert: FamilyAlert) -> Bool {
        !persona.isParent && alert.decision == nil
    }

    @discardableResult
    func decide(_ verdict: Verdict, on alertID: UUID) -> DecisionOutcome {
        guard !persona.isParent else { return .unknownAlert }
        return relay.submit(GuardianDecision(by: currentPerson, verdict: verdict, at: .now), for: alertID)
    }

    /// Demo: pengawas lain menjawab lebih dulu, untuk memperlihatkan tombol yang terkunci.
    @discardableResult
    func simulateDecision(by person: Person, _ verdict: Verdict, on alertID: UUID) -> DecisionOutcome {
        relay.submit(GuardianDecision(by: person, verdict: verdict, at: .now), for: alertID)
    }

    func openAlert(_ id: UUID) {
        guardianTab = .home
        guardianPath = [id]
        toast = nil
    }

    // MARK: Event dari relay

    private func handle(_ event: RelayEvent) {
        switch event {
        case .alert(let alert):
            let isNew = !alerts.contains { $0.id == alert.id }
            if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
                alerts[index] = alert
            } else {
                alerts.insert(alert, at: 0)
            }
            if isNew, !persona.isParent {
                present(Toast(id: "alert-\(alert.id)", title: "\(alert.level.title): \(alert.title)",
                              body: "Ketuk untuk melihat kalimatnya dan memutuskan.",
                              level: alert.level, alertID: alert.id))
            }

        case .decided(let alertID, let decision):
            if let index = alerts.firstIndex(where: { $0.id == alertID }) {
                alerts[index].decision = decision
            }
            if let index = history.firstIndex(where: { $0.id == alertID }) {
                history[index].decision = decision
            }
            if let session, session.id == alertID {
                liveActivity.update(activityState(for: session))
            }
            if decision.by != currentPerson {
                let scam = decision.verdict == .scam
                present(Toast(
                    id: "decision-\(alertID)",
                    title: scam ? "\(decision.by.name): ini penipuan" : "\(decision.by.name): telepon aman",
                    body: persona.isParent
                        ? (scam ? "Tutup telepon sekarang." : "Tetap jangan beri kode atau transfer.")
                        : "Sudah dikirim ke \(parent.name).",
                    level: scam ? .danger : .safe,
                    alertID: alertID
                ))
            }
        }
    }

    private func activityState(for session: CallSession) -> RambuCallAttributes.ContentState {
        let decision = alerts.first { $0.id == session.id }?.decision
        return RambuCallAttributes.ContentState(
            level: session.level,
            headline: session.headline,
            isListening: session.isListening,
            decidedBy: decision?.by.name,
            decisionIsScam: decision.map { $0.verdict == .scam }
        )
    }
}

