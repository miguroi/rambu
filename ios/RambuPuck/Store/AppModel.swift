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

    let parent = Person.ratna
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
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    init(
        persona: Persona = .ratna,
        onboardingComplete: Bool = false,
        analysis: any CallAnalysisSource = ScenarioAnalysis(),
        relay: (any FamilyRelay)? = nil,
        liveActivities: Bool = true,
        now: Date = .now
    ) {
        self.persona = persona
        self.onboardingComplete = onboardingComplete
        self.puck = onboardingComplete ? .demo : .unpaired
        self.history = CallRecord.seed(now: now)
        self.analysis = analysis
        self.relay = relay ?? LocalFamilyRelay()
        self.liveActivity = CallLiveActivity(enabled: liveActivities)
        self.relay.onEvent = { [weak self] event in self?.handle(event) }
    }

    var currentPerson: Person { persona.person }

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

    // MARK: Onboarding & demo

    func completeOnboarding(as persona: Persona) {
        self.persona = persona
        puck = .demo
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
        puck = .unpaired
        onboardingComplete = false
        onboardingStep = .welcome
    }

    // MARK: Orang tua

    /// Memulai panggilan simulasi. Mengembalikan task pendengar supaya tes bisa menunggunya.
    @discardableResult
    func startCall(_ scenario: Scenario) -> Task<Void, Never> {
        listenTask?.cancel()
        if let old = session { liveActivity.end(state: activityState(for: old), dismissImmediately: true) }

        let session = CallSession(id: UUID(), scenario: scenario, startedAt: .now)
        self.session = session
        persona = .ratna
        isCallScreenPresented = true

        liveActivity.start(
            attributes: RambuCallAttributes(parentName: parent.name, channel: scenario.channel.short, startedAt: session.startedAt),
            state: activityState(for: session)
        )

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

        liveActivity.update(activityState(for: current))

        guard current.level.relaysToGuardians else { return }
        if current.level > previous || chunk.line.isFlagged {
            relay.publish(makeAlert(from: current))
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
            if isNew, !persona.isParent { toast = .alert(alert.id) }

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
            if decision.by != currentPerson, !(persona.isParent && isCallScreenPresented) {
                toast = .decision(alertID, decision)
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
