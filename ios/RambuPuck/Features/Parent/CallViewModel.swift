import Foundation
import Observation

/// Mengelola satu siklus telepon, analisis potongan audio, dan Live Activity.
@MainActor
@Observable
final class CallViewModel {
    @ObservationIgnored let state: AppState
    @ObservationIgnored private let analysis: any CallAnalysisSource
    @ObservationIgnored private let family: FamilyViewModel
    @ObservationIgnored private let pilot: PilotViewModel
    @ObservationIgnored private let profile: ProfileViewModel
    @ObservationIgnored private let liveActivity: CallLiveActivity
    @ObservationIgnored private let escalationDelay: Duration
    @ObservationIgnored private let speakerCheckDelay: Duration
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var escalationTask: Task<Void, Never>?
    @ObservationIgnored private var speakerTask: Task<Void, Never>?

    init(
        state: AppState,
        analysis: any CallAnalysisSource,
        family: FamilyViewModel,
        pilot: PilotViewModel,
        profile: ProfileViewModel,
        liveActivity: CallLiveActivity,
        escalationDelay: Duration,
        speakerCheckDelay: Duration
    ) {
        self.state = state
        self.analysis = analysis
        self.family = family
        self.pilot = pilot
        self.profile = profile
        self.liveActivity = liveActivity
        self.escalationDelay = escalationDelay
        self.speakerCheckDelay = speakerCheckDelay
        family.currentActivityState = { [weak self] session in
            self?.activityState(for: session) ?? Self.fallbackActivityState(for: session)
        }
        family.onDecision = { [weak self] in self?.escalationTask?.cancel() }
    }

    @discardableResult
    func start(_ template: Scenario) -> Task<Void, Never> {
        let scenario = template.personalized(parentName: state.parent.name)
        cancelTasks()
        if let old = state.session {
            liveActivity.end(state: activityState(for: old), dismissImmediately: true)
        }

        var session = CallSession(id: UUID(), scenario: scenario, startedAt: .now)
        session.speakerOn = !state.speakerOffNextCall
        state.speakerOffNextCall = false
        state.session = session
        state.persona = .ratna
        state.toast = nil
        state.showCallStatus = false
        state.isCallScreenPresented = true

        guard session.speakerOn else {
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

    @discardableResult
    func turnOnSpeaker() -> Task<Void, Never>? {
        guard var current = state.session, !current.speakerOn else { return nil }
        current.speakerOn = true
        state.session = current
        speakerTask?.cancel()
        if state.toast?.id.hasPrefix("speaker-") == true { state.toast = nil }
        return beginListening(current)
    }

    func end() {
        guard let session = state.session else { return }
        cancelTasks()

        let alert = state.alerts.first { $0.id == session.id }
        if session.level > .safe {
            state.history.insert(CallRecord(
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
            ), at: 0)
        }
        if let index = state.alerts.firstIndex(where: { $0.id == session.id }) {
            state.alerts[index].callEnded = true
        }
        pilot.end(session.id)

        var final = activityState(for: session)
        final.isListening = false
        liveActivity.end(state: final)

        state.session = nil
        state.showCallStatus = false
        state.isCallScreenPresented = false
        if state.toast?.id.hasPrefix("speaker-") == true { state.toast = nil }
        profile.persist()
    }

    func cancel() {
        cancelTasks()
        if let session = state.session {
            liveActivity.end(state: activityState(for: session), dismissImmediately: true)
        }
        state.session = nil
    }

    private func cancelTasks() {
        listenTask?.cancel()
        escalationTask?.cancel()
        speakerTask?.cancel()
        listenTask = nil
        escalationTask = nil
        speakerTask = nil
    }

    private func remindSpeaker(for id: UUID) {
        guard let session = state.session, session.id == id, !session.speakerOn else { return }
        profile.present(Toast(
            id: "speaker-\(id)",
            title: "Nyalakan loudspeaker",
            body: "Rambu belum mendengar suara telepon. Ketuk Speaker supaya bisa ikut menjaga.",
            level: .review,
            alertID: nil
        ))
    }

    private func beginListening(_ session: CallSession) -> Task<Void, Never> {
        let context = CallContext(
            id: session.id,
            channel: session.scenario.channel,
            startedAt: session.startedAt,
            scenario: session.scenario
        )
        let stream = analysis.assessments(for: context)
        let sessionID = session.id
        let task = Task { [weak self] in
            for await chunk in stream {
                guard !Task.isCancelled else { return }
                self?.ingest(chunk, sessionID: sessionID)
            }
        }
        listenTask = task
        return task
    }

    private func ingest(_ chunk: ChunkAssessment, sessionID: UUID) {
        guard var current = state.session, current.id == sessionID else { return }
        let previous = current.level

        current.heard.append(chunk.line)
        for signal in chunk.signals where !current.signals.contains(signal) {
            current.signals.append(signal)
        }
        current.level = max(current.level, chunk.level)
        state.session = current

        guard current.level.relaysToGuardians else { return }
        if liveActivity.isActive {
            liveActivity.update(activityState(for: current))
        } else {
            liveActivity.start(
                attributes: RambuCallAttributes(
                    parentName: state.parent.name,
                    channel: current.scenario.channel.short,
                    startedAt: current.startedAt
                ),
                state: activityState(for: current)
            )
        }

        let isFirstAlert = !state.alerts.contains { $0.id == current.id }
        if current.level > previous || chunk.line.isFlagged {
            let alert = makeAlert(from: current)
            family.publish(alert)
            pilot.publish(alert)
        }
        if isFirstAlert { scheduleEscalation(for: current.id) }
        if current.level > previous, state.persona.isParent {
            profile.present(parentWarning(for: current))
        }
    }

    private func scheduleEscalation(for id: UUID) {
        escalationTask?.cancel()
        escalationTask = Task { [weak self, escalationDelay] in
            try? await Task.sleep(for: escalationDelay)
            guard !Task.isCancelled else { return }
            self?.escalate(id)
        }
    }

    private func escalate(_ id: UUID) {
        guard let alert = state.alerts.first(where: { $0.id == id }),
              alert.decision == nil,
              state.session?.id == id else { return }
        state.unanswered.insert(id)
        if state.persona.isParent {
            profile.present(Toast(
                id: "unanswered-\(id)",
                title: "Belum ada jawaban",
                body: "Pengawas belum menjawab. Jangan lakukan tindakan apa pun dulu.",
                level: alert.level,
                alertID: id
            ))
        } else {
            profile.present(Toast(
                id: "unanswered-\(id)",
                title: "\(alert.parent.name) menunggu jawaban",
                body: "Belum ada pengawas yang menjawab peringatan.",
                level: alert.level,
                alertID: id
            ))
        }
    }

    private func makeAlert(from session: CallSession) -> FamilyAlert {
        let existing = state.alerts.first { $0.id == session.id }
        return FamilyAlert(
            id: session.id,
            parent: state.parent,
            callerDetail: session.scenario.callerDetail,
            channel: session.scenario.channel,
            startedAt: session.startedAt,
            raisedAt: existing?.raisedAt ?? .now,
            level: session.level,
            signals: session.signals,
            evidence: session.heard.filter { $0.speaker == .caller && $0.isFlagged },
            recipients: state.guardians,
            decision: existing?.decision
        )
    }

    private func parentWarning(for session: CallSession) -> Toast {
        let names = state.guardians.map(\.name).formatted(.list(type: .and).locale(Fmt.locale))
        let delivery = state.guardians.isEmpty ? "Belum ada pengawas terhubung." : "Sudah dikirim ke \(names)."
        let danger = session.level == .danger
        return Toast(
            id: "\(session.id)-\(session.level.rawValue)",
            title: danger ? "Bahaya: terindikasi penipuan" : "Waspada: telepon mencurigakan",
            body: danger
                ? "Hati-hati. Jangan transfer atau sebut kode. \(delivery)"
                : "\(session.headline). Jangan beri data dulu. \(delivery)",
            level: session.level,
            alertID: session.id
        )
    }

    func activityState(for session: CallSession) -> RambuCallAttributes.ContentState {
        let decision = state.alerts.first { $0.id == session.id }?.decision
        return RambuCallAttributes.ContentState(
            level: session.level,
            headline: session.headline,
            isListening: session.isListening,
            decidedBy: decision?.by.name,
            decisionIsScam: decision.map { $0.verdict == .scam }
        )
    }

    private static func fallbackActivityState(for session: CallSession) -> RambuCallAttributes.ContentState {
        RambuCallAttributes.ContentState(
            level: session.level,
            headline: session.headline,
            isListening: session.isListening,
            decidedBy: nil,
            decisionIsScam: nil
        )
    }
}
