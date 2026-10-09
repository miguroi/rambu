import Foundation

struct ProtectionConnection: Sendable {
    let serverURL: String
    let accessToken: String
}

struct ProtectionCallAnalysisSource: CallAnalysisSource {
    let connection: @Sendable () -> ProtectionConnection?
    let session: any HTTPDataSession
    let pollInterval: Duration
    let usesAuthoritativeRemoteAlerts = true

    init(
        serverURL: String,
        accessToken: @escaping @Sendable () -> String?,
        session: any HTTPDataSession = URLSession.shared,
        pollInterval: Duration = .milliseconds(700)
    ) {
        connection = {
            ProtectionConnection(serverURL: serverURL, accessToken: accessToken() ?? "")
        }
        self.session = session
        self.pollInterval = pollInterval
    }

    init(
        connection: @escaping @Sendable () -> ProtectionConnection?,
        session: any HTTPDataSession = URLSession.shared,
        pollInterval: Duration = .milliseconds(700)
    ) {
        self.connection = connection
        self.session = session
        self.pollInterval = pollInterval
    }

    func start(for call: CallContext) async throws -> any CallAnalysisSession {
        guard let connection = connection() else {
            throw BackendAnalysisError.session(
                code: "missing_parent_token",
                detail: "Hubungkan akun orang tua sebelum memantau panggilan."
            )
        }
        let api = try ProtectionAPI(
            serverURL: connection.serverURL,
            token: connection.accessToken,
            session: session
        )
        let initial = try await api.create(call: call)
        return ProtectionRemoteSession(api: api, initial: initial, pollInterval: pollInterval)
    }

    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var remote: (any CallAnalysisSession)?
                do {
                    let started = try await start(for: call)
                    remote = started
                    for try await value in started.assessments {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    if let remote { try? await remote.cancel() }
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class ProtectionRemoteSession: CallAnalysisSession, @unchecked Sendable {
    let assessments: AsyncThrowingStream<ChunkAssessment, Error>
    let statusUpdates: AsyncStream<ProtectionStatus>

    private let api: ProtectionAPI
    private let id: String
    private let pollInterval: Duration
    private let assessmentContinuation: AsyncThrowingStream<ChunkAssessment, Error>.Continuation
    private let statusContinuation: AsyncStream<ProtectionStatus>.Continuation
    private let lock = NSLock()
    private var pollingTask: Task<Void, Never>?
    private var lastRevision = -1
    private var lastStatus: ProtectionStatus?
    private var seenAssessments = Set<ProtectionAssessmentDTO>()
    private var seenEvidence = Set<ProtectionEvidenceDTO>()
    private var nextLineID = 0
    private var cancelled = false
    private var finishRequested = false

    init(api: ProtectionAPI, initial: ProtectionSnapshotDTO, pollInterval: Duration) {
        var capturedAssessment: AsyncThrowingStream<ChunkAssessment, Error>.Continuation!
        assessments = AsyncThrowingStream { capturedAssessment = $0 }
        assessmentContinuation = capturedAssessment
        var capturedStatus: AsyncStream<ProtectionStatus>.Continuation!
        statusUpdates = AsyncStream { capturedStatus = $0 }
        statusContinuation = capturedStatus
        self.api = api
        id = initial.id
        self.pollInterval = pollInterval
        pollingTask = Task { [weak self] in
            await self?.poll(startingWith: initial)
        }
    }

    func finish() async throws {
        let shouldFinish = lock.withLock {
            guard !finishRequested, !cancelled else { return false }
            finishRequested = true
            return true
        }
        guard shouldFinish else { return }
        do {
            let snapshot = try await api.end(id: id)
            _ = try process(snapshot)
        } catch {
            fail(error)
            throw error
        }
    }

    func cancel() async throws {
        let shouldCancel = lock.withLock {
            guard !cancelled else { return false }
            cancelled = true
            return true
        }
        guard shouldCancel else { return }
        pollingTask?.cancel()
        do {
            try await api.delete(id: id)
            assessmentContinuation.finish()
            statusContinuation.finish()
        } catch {
            fail(error)
            throw error
        }
    }

    private func poll(startingWith initial: ProtectionSnapshotDTO) async {
        do {
            var snapshot = initial
            while true {
                if try process(snapshot) { return }
                try await Task.sleep(for: pollInterval)
                try Task.checkCancellation()
                snapshot = try await api.status(id: id)
            }
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    @discardableResult
    private func process(_ snapshot: ProtectionSnapshotDTO) throws -> Bool {
        if snapshot.status == "error" {
            guard let failure = snapshot.failure else {
                throw BackendAnalysisError.schema(detail: "Sesi gagal tanpa keterangan.")
            }
            throw BackendAnalysisError.session(code: failure.code, detail: failure.message)
        }

        let status: ProtectionStatus
        switch snapshot.status {
        case "waiting_for_puck": status = .waitingForPuck
        case "listening": status = .listening
        case "completed": status = snapshot.outcome == "no_speech" ? .noSpeech : .completed
        default:
            throw BackendAnalysisError.schema(detail: "Status sesi backend tidak dikenal.")
        }

        let values: (emitStatus: Bool, assessment: ProtectionAssessmentDTO?) = lock.withLock {
            guard snapshot.revision > lastRevision else { return (false, nil) }
            lastRevision = snapshot.revision
            let emitStatus = status != lastStatus
            lastStatus = status
            let assessment = snapshot.assessment.flatMap {
                seenAssessments.insert($0).inserted ? $0 : nil
            }
            return (emitStatus, assessment)
        }
        if values.emitStatus { statusContinuation.yield(status) }
        if let assessment = values.assessment {
            try emit(assessment, transcript: snapshot.maskedTranscript)
        }

        if snapshot.status == "completed" {
            assessmentContinuation.finish()
            statusContinuation.finish()
            return true
        }
        return false
    }

    private func emit(_ assessment: ProtectionAssessmentDTO, transcript: String) throws {
        let level = try riskLevel(assessment.riskLevel)
        let topSignals = try assessment.signals.map(signal)
        if level == .safe {
            guard topSignals.isEmpty, assessment.evidence.isEmpty else {
                throw BackendAnalysisError.schema(detail: "Risiko rendah berisi bukti yang tidak valid.")
            }
            return
        }
        guard !topSignals.isEmpty, !assessment.evidence.isEmpty else {
            throw BackendAnalysisError.schema(detail: "Hasil berisiko tidak memiliki bukti.")
        }
        for evidence in assessment.evidence {
            let evidenceSignals = try evidence.signals.map(signal)
            guard !evidenceSignals.isEmpty,
                  evidenceSignals.allSatisfy(topSignals.contains),
                  transcript.contains(evidence.quote) else {
                throw BackendAnalysisError.schema(detail: "Bukti analisis tidak sesuai transkrip.")
            }
            let lineID: Int? = lock.withLock {
                guard seenEvidence.insert(evidence).inserted else { return nil }
                defer { nextLineID += 1 }
                return nextLineID
            }
            guard let lineID else { continue }
            assessmentContinuation.yield(ChunkAssessment(
                line: TranscriptLine(
                    id: lineID,
                    offset: nil,
                    speaker: .unknown,
                    text: evidence.quote,
                    flagged: [evidence.quote],
                    signals: evidenceSignals
                ),
                level: level,
                signals: evidenceSignals
            ))
        }
    }

    private func fail(_ error: Error) {
        assessmentContinuation.finish(throwing: error)
        statusContinuation.finish()
    }

    private func riskLevel(_ value: String) throws -> RiskLevel {
        switch value {
        case "low": .safe
        case "needs_review": .danger
        case "high_risk": .danger
        default: throw BackendAnalysisError.schema(detail: "Tingkat risiko backend tidak dikenal.")
        }
    }

    private func signal(_ value: String) throws -> SignalKind {
        switch value {
        case "impersonation": .impersonation
        case "urgency": .urgency
        case "secret_code": .secretCode
        case "transfer": .transfer
        case "remote_app": .remoteApp
        default: throw BackendAnalysisError.schema(detail: "Jenis tanda backend tidak dikenal.")
        }
    }
}
