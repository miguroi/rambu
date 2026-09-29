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
    /// Orang tua lain yang dijaga pengawas di HP ini, selain `parent`.
    var extraParents: [Person] = []

    var session: CallSession?
    var isCallScreenPresented = false
    var alerts: [FamilyAlert] = []
    var history: [CallRecord]
    /// Peringatan yang sudah melewati batas waktu tanpa jawaban pengawas.
    var unanswered: Set<UUID> = []

    var parentTab: ParentTab = .home
    var guardianTab: GuardianTab = .home
    var guardianPath: [UUID] = []
    var showDemoSheet = false
    var showProfile = false
    var showCallStatus = false
    var toast: Toast?

    // Pengaturan dan keadaan perangkat
    var narrationEnabled = true
    var notificationsAuthorized = false
    var isOnline = true
    var pendingInviteCode: String?

    // Simulasi gangguan untuk demo
    var simulateOffline = false
    var bluetoothOn = true
    /// Riset nomor 11: puck mengukur volume di awal telepon. Kalau terlalu pelan, loudspeaker belum menyala.
    var speakerOffNextCall = false
    /// Hanya untuk screenshot: sembunyikan banner notifikasi mati.
    var hidesNotificationIssue = false

    @ObservationIgnored private let analysis: any CallAnalysisSource
    @ObservationIgnored private let relay: any FamilyRelay
    @ObservationIgnored private let liveActivity: CallLiveActivity
    @ObservationIgnored private let notifier: RambuNotifier
    @ObservationIgnored private let narrator: Narrator
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored let feedback: any DetectionFeedback
    @ObservationIgnored private let store: LocalStore?
    @ObservationIgnored private let escalationDelay: Duration
    @ObservationIgnored private let speakerCheckDelay: Duration
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var escalationTask: Task<Void, Never>?
    @ObservationIgnored private var speakerTask: Task<Void, Never>?

    init(
        persona: Persona = .ratna,
        onboardingComplete: Bool = false,
        analysis: any CallAnalysisSource = ScenarioAnalysis(),
        relay: (any FamilyRelay)? = nil,
        liveActivities: Bool = true,
        notifications: Bool = true,
        speech: Bool = true,
        store: LocalStore? = nil,
        escalationDelay: Duration = .seconds(60),
        speakerCheckDelay: Duration = .seconds(3),
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
        self.narrator = Narrator(enabled: speech)
        self.feedback = LocalDetectionFeedback()
        self.store = store
        self.escalationDelay = escalationDelay
        self.speakerCheckDelay = speakerCheckDelay

        if let saved = store?.load() { restore(saved) }

        self.relay.onEvent = { [weak self] event in self?.handle(event) }
        self.notifier.onOpen = { [weak self] id in self?.openFromPush(id) }
        if notifications {
            network.onChange = { [weak self] online in self?.isOnline = online }
            network.start()
            Task { await refreshNotificationStatus() }
        }
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

    /// Semua orang tua yang dijaga pengawas di HP ini.
    var protectedParents: [Person] { [parent] + extraParents }

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

    // MARK: Profil

    func renameParent(_ name: String) {
        parent = parent.renamed(name)
        persist()
    }

    func renameGuardian(_ persona: Persona, name: String, relation: String) {
        let index = persona == .richard ? 1 : 0
        guard guardians.indices.contains(index) else { return }
        guardians[index] = guardians[index].renamed(name, relation: relation)
        persist()
    }

    /// Minimal satu pengawas harus tersisa, supaya peringatan selalu punya penerima.
    func removeGuardian(_ person: Person) {
        guard guardians.count > 1 else { return }
        guardians.removeAll { $0 == person }
        persist()
    }

    /// Pengawas bergabung menjaga orang tua lain lewat kode. Di demo, kode mana pun
    /// menghasilkan orang tua contoh berikutnya.
    @discardableResult
    func addProtectedParent(code: String) -> Person? {
        guard code.count == 6 else { return nil }
        let samples = [
            Person(id: "hadi", name: "Pak Hadi", initial: "H", relation: "Ayah", colorHex: 0x8A5A12),
            Person(id: "lies", name: "Oma Lies", initial: "L", relation: "Nenek", colorHex: 0xA23B72),
        ]
        guard let next = samples.first(where: { sample in !extraParents.contains(sample) }) else { return nil }
        extraParents.append(next)
        persist()
        return next
    }

    func removeProtectedParent(_ person: Person) {
        extraParents.removeAll { $0 == person }
        persist()
    }

    func clearHistory() {
        history = []
        persist()
    }

    func setNarration(_ on: Bool) {
        narrationEnabled = on
        if !on { narrator.stop() }
        persist()
    }

    /// Bacakan teks pendek kalau narasi dinyalakan.
    func narrate(_ text: String) {
        guard narrationEnabled else { return }
        narrator.speak(text)
    }

    func stopNarration() {
        narrator.stop()
    }

    // MARK: Gangguan

    var issues: [SystemIssue] {
        guard onboardingComplete else { return [] }
        var list: [SystemIssue] = []
        if !notificationsAuthorized && !hidesNotificationIssue { list.append(.notificationsOff) }
        if !isOnline || simulateOffline { list.append(.offline) }
        if persona.isParent {
            if !bluetoothOn {
                list.append(.bluetoothOff)
            } else if !puck.isConnected {
                list.append(.puckDisconnected)
            } else if puck.battery <= 20 {
                list.append(.puckLowBattery)
            }
        }
        return list
    }

    func refreshNotificationStatus() async {
        await notifier.refresh()
        notificationsAuthorized = notifier.isAuthorized
    }

    func requestNotifications() async {
        await notifier.requestAuthorization()
        notificationsAuthorized = notifier.isAuthorized
    }

    /// Demo: puck tersambung lagi setelah didekatkan.
    func reconnectPuck() async {
        try? await Task.sleep(for: .seconds(1.2))
        bluetoothOn = true
        puck.isConnected = true
    }

    // MARK: Push

    /// Push sistem kalau diizinkan, tiruan banner di dalam app kalau belum.
    /// Push untuk orang tua ikut dibacakan kalau narasi menyala.
    private func present(_ push: Toast) {
        if notifier.isAuthorized {
            notifier.post(push)
        } else {
            toast = push
        }
        if persona.isParent { narrate("\(push.title). \(push.body)") }
    }

    private func openFromPush(_ id: UUID?) {
        toast = nil
        if persona.isParent {
            if session != nil { showCallStatus = true } else { parentTab = .history }
        } else if let id {
            openAlert(id)
        }
    }

    /// Ketukan pada tiruan banner push.
    func openToast(_ toast: Toast) {
        openFromPush(toast.alertID)
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
        pendingInviteCode = nil
        persist()
    }

    func switchPersona(_ persona: Persona) {
        self.persona = persona
        guardianPath = []
        toast = nil
        showCallStatus = false
        if persona.isParent, session != nil { isCallScreenPresented = true }
        persist()
    }

    func resetDemo() {
        listenTask?.cancel()
        escalationTask?.cancel()
        speakerTask?.cancel()
        listenTask = nil
        if let session { liveActivity.end(state: activityState(for: session), dismissImmediately: true) }
        session = nil
        isCallScreenPresented = false
        showCallStatus = false
        showProfile = false
        alerts = []
        unanswered = []
        history = CallRecord.seed()
        toast = nil
        guardianPath = []
        parentTab = .home
        guardianTab = .home
        persona = .ratna
        parent = .ratna
        guardians = Person.guardians
        extraParents = []
        puck = .unpaired
        bluetoothOn = true
        simulateOffline = false
        speakerOffNextCall = false
        onboardingComplete = false
        onboardingStep = .welcome
        store?.clear()
    }

    /// Tautan undangan dari WhatsApp: `rambu://gabung?kode=…` atau tautan https-nya.
    func handleIncoming(_ url: URL) {
        guard let code = InviteLink.code(from: url) else { return }
        if !onboardingComplete {
            pendingInviteCode = code
            onboardingStep = .enterCode
        } else if !persona.isParent, let added = addProtectedParent(code: code) {
            toast = Toast(id: "joined-\(added.id)", title: "Sekarang Anda menjaga \(added.name)",
                          body: "Peringatan dari HP \(added.name) akan masuk ke sini.", level: .safe, alertID: nil)
        } else if persona.isParent {
            toast = Toast(id: "link-parent", title: "Tautan ini untuk pengawas",
                          body: "Kirim ke HP anak Anda.", level: .safe, alertID: nil)
        }
    }

    // MARK: Orang tua

    /// Memulai panggilan simulasi. Mengembalikan task pendengar supaya tes bisa menunggunya.
    @discardableResult
    func startCall(_ template: Scenario) -> Task<Void, Never> {
        let scenario = template.personalized(parentName: parent.name)
        listenTask?.cancel()
        escalationTask?.cancel()
        speakerTask?.cancel()
        if let old = session { liveActivity.end(state: activityState(for: old), dismissImmediately: true) }

        var session = CallSession(id: UUID(), scenario: scenario, startedAt: .now)
        session.speakerOn = !speakerOffNextCall
        speakerOffNextCall = false
        self.session = session
        persona = .ratna
        toast = nil
        showCallStatus = false
        isCallScreenPresented = true
        // Telepon yang aman tidak memunculkan apa pun. Live Activity dan push baru muncul
        // begitu ada tanda penipuan (lihat ingest).

        guard session.speakerOn else {
            // Puck mengukur volume beberapa detik. Kalau tetap sunyi, orang tua diingatkan.
            let id = session.id
            let task = Task { [weak self, speakerCheckDelay] in
                try? await Task.sleep(for: speakerCheckDelay)
                guard !Task.isCancelled else { return }
                self?.remindSpeaker(for: id)
            }
            speakerTask = task
            return task
        }
        return beginListening(session)
    }

    private func remindSpeaker(for id: UUID) {
        guard let session, session.id == id, !session.speakerOn else { return }
        present(Toast(id: "speaker-\(id)", title: "Nyalakan loudspeaker",
                      body: "Rambu belum mendengar suara telepon. Ketuk Speaker supaya bisa ikut menjaga.",
                      level: .review, alertID: nil))
    }

    /// Orang tua menyalakan loudspeaker: puck mulai mendengar.
    @discardableResult
    func turnOnSpeaker() -> Task<Void, Never>? {
        guard var current = session, !current.speakerOn else { return nil }
        current.speakerOn = true
        session = current
        speakerTask?.cancel()
        if toast?.id.hasPrefix("speaker-") == true { toast = nil }
        return beginListening(current)
    }

    private func beginListening(_ session: CallSession) -> Task<Void, Never> {
        let context = CallContext(id: session.id, channel: session.scenario.channel,
                                  startedAt: session.startedAt, scenario: session.scenario)
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

        let isFirstAlert = !alerts.contains { $0.id == current.id }
        if current.level > previous || chunk.line.isFlagged {
            relay.publish(makeAlert(from: current))
        }
        if isFirstAlert { scheduleEscalation(for: current.id) }
        if current.level > previous, persona.isParent {
            present(parentWarning(for: current))
        }
    }

    /// Kalau tidak ada pengawas yang menjawab dalam batas waktu, orang tua diminta menahan diri.
    private func scheduleEscalation(for id: UUID) {
        escalationTask?.cancel()
        escalationTask = Task { [weak self, escalationDelay] in
            try? await Task.sleep(for: escalationDelay)
            guard !Task.isCancelled else { return }
            self?.escalate(id)
        }
    }

    private func escalate(_ id: UUID) {
        guard let alert = alerts.first(where: { $0.id == id }), alert.decision == nil, session?.id == id else { return }
        unanswered.insert(id)
        if persona.isParent {
            present(Toast(id: "unanswered-\(id)", title: "Belum ada jawaban",
                          body: "Pengawas belum menjawab. Jangan lakukan tindakan apa pun dulu.",
                          level: alert.level, alertID: id))
        } else {
            present(Toast(id: "unanswered-\(id)", title: "\(alert.parent.name) menunggu jawaban",
                          body: "Belum ada pengawas yang menjawab peringatan.", level: alert.level, alertID: id))
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
        escalationTask?.cancel()
        speakerTask?.cancel()
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
        showCallStatus = false
        isCallScreenPresented = false
        if toast?.id.hasPrefix("speaker-") == true { toast = nil }
        persist()
    }

    // MARK: Pengawas

    func canDecide(_ alert: FamilyAlert) -> Bool {
        !persona.isParent && alert.decision == nil
    }

    /// Server menjalankan aturan jawaban pertama. Kalau kalah cepat, jawaban ditolak
    /// dan pengawas diberi tahu siapa yang lebih dulu.
    @discardableResult
    func decide(_ verdict: Verdict, on alertID: UUID) -> DecisionOutcome {
        guard !persona.isParent else { return .unknownAlert }
        let outcome = relay.submit(GuardianDecision(by: currentPerson, verdict: verdict, at: .now), for: alertID)
        if case .alreadyDecided(let existing) = outcome, existing.by != currentPerson {
            toast = Toast(
                id: "late-\(alertID)",
                title: "\(existing.by.name) sudah menjawab lebih dulu",
                body: "Jawabannya: \(existing.verdict.pastTitle). Cukup satu jawaban.",
                level: existing.verdict == .scam ? .danger : .safe,
                alertID: alertID
            )
        }
        return outcome
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
            escalationTask?.cancel()
            unanswered.remove(alertID)
            if let index = alerts.firstIndex(where: { $0.id == alertID }) {
                alerts[index].decision = decision
                if decision.verdict == .safe {
                    feedback.reportFalsePositive(alertID: alertID, signals: alerts[index].signals)
                }
            }
            if let index = history.firstIndex(where: { $0.id == alertID }) {
                history[index].decision = decision
                persist()
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

    // MARK: Penyimpanan

    private func persist() {
        store?.save(SavedState(
            onboardingComplete: onboardingComplete,
            persona: persona,
            parent: parent,
            guardians: guardians,
            extraParents: extraParents,
            history: history,
            puck: puck,
            narrationEnabled: narrationEnabled
        ))
    }

    private func restore(_ saved: SavedState) {
        onboardingComplete = saved.onboardingComplete
        persona = saved.persona
        parent = saved.parent
        guardians = saved.guardians
        extraParents = saved.extraParents
        history = saved.history
        puck = saved.puck
        narrationEnabled = saved.narrationEnabled
    }
}
