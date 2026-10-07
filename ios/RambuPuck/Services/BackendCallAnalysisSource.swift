import Foundation

protocol HTTPDataSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataSession {}

enum BackendAnalysisError: Error, Equatable, LocalizedError, Sendable {
    case invalidServerURL
    case invalidScenario
    case transport(detail: String)
    case http(status: Int, detail: String)
    case decoding
    case schema(detail: String)
    case session(code: String, detail: String)

    var code: String {
        switch self {
        case .invalidServerURL: "invalid_server_url"
        case .invalidScenario: "invalid_scenario"
        case .transport: "transport"
        case .http(let status, _): "http_\(status)"
        case .decoding: "decoding"
        case .schema: "schema"
        case .session(let code, _): code
        }
    }

    var detail: String {
        switch self {
        case .invalidServerURL:
            "Alamat server Rambu tidak valid."
        case .invalidScenario:
            "Skenario panggilan tidak tersedia."
        case .transport(let detail), .schema(let detail), .session(_, let detail):
            detail
        case .http(_, let detail):
            detail
        case .decoding:
            "Respons server Rambu tidak dapat dibaca."
        }
    }

    var errorDescription: String? { detail }
}

struct BackendCallAnalysisSource: CallAnalysisSource {
    let serverURL: String
    let session: any HTTPDataSession
    let pollInterval: Duration

    init(
        serverURL: String,
        session: any HTTPDataSession = URLSession.shared,
        pollInterval: Duration = .milliseconds(700)
    ) {
        self.serverURL = serverURL
        self.session = session
        self.pollInterval = pollInterval
    }

    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var remoteID: String?
                do {
                    let baseURL = try validatedBaseURL()
                    guard let scenarioID = call.metadata.fixtureID else {
                        throw BackendAnalysisError.invalidScenario
                    }

                    var request = URLRequest(url: endpoint(baseURL, "api", "demo", scenarioID))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    var snapshot = try await snapshot(for: request)
                    remoteID = snapshot.id

                    var seenAssessments = Set<AssessmentDTO>()
                    var seenEvidence = Set<EvidenceDTO>()
                    var nextLineID = 0
                    try yieldNewEvidence(
                        from: snapshot,
                        seenAssessments: &seenAssessments,
                        seenEvidence: &seenEvidence,
                        nextLineID: &nextLineID,
                        continuation: continuation
                    )

                    while snapshot.status == "running" {
                        try await Task.sleep(for: pollInterval)
                        try Task.checkCancellation()
                        let statusRequest = URLRequest(url: endpoint(baseURL, "api", "demo", snapshot.id))
                        snapshot = try await self.snapshot(for: statusRequest)
                        try yieldNewEvidence(
                            from: snapshot,
                            seenAssessments: &seenAssessments,
                            seenEvidence: &seenEvidence,
                            nextLineID: &nextLineID,
                            continuation: continuation
                        )
                    }

                    try terminalError(from: snapshot)
                    if let remoteID { await delete(remoteID, from: baseURL) }
                    continuation.finish()
                } catch let error as BackendAnalysisError {
                    if let remoteID, let baseURL = try? validatedBaseURL() {
                        await delete(remoteID, from: baseURL)
                    }
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    if let remoteID, let baseURL = try? validatedBaseURL() {
                        await delete(remoteID, from: baseURL)
                    }
                    continuation.finish(throwing: CancellationError())
                } catch {
                    if let remoteID, let baseURL = try? validatedBaseURL() {
                        await delete(remoteID, from: baseURL)
                    }
                    continuation.finish(
                        throwing: BackendAnalysisError.transport(
                            detail: "Server Rambu tidak dapat dihubungi."
                        )
                    )
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func validatedBaseURL() throws -> URL {
        let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else {
            throw BackendAnalysisError.invalidServerURL
        }
        return url
    }

    private func endpoint(_ baseURL: URL, _ components: String...) -> URL {
        components.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
    }

    private func snapshot(for request: URLRequest) async throws -> SnapshotDTO {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BackendAnalysisError.transport(detail: "Server Rambu tidak dapat dihubungi.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendAnalysisError.transport(detail: "Respons jaringan Rambu tidak valid.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendAnalysisError.http(
                status: http.statusCode,
                detail: Self.errorDetail(from: data) ?? "Server mengembalikan status \(http.statusCode)."
            )
        }
        do {
            return try Self.decoder.decode(SnapshotDTO.self, from: data)
        } catch {
            throw BackendAnalysisError.decoding
        }
    }

    private func yieldNewEvidence(
        from snapshot: SnapshotDTO,
        seenAssessments: inout Set<AssessmentDTO>,
        seenEvidence: inout Set<EvidenceDTO>,
        nextLineID: inout Int,
        continuation: AsyncThrowingStream<ChunkAssessment, Error>.Continuation
    ) throws {
        try terminalError(from: snapshot)
        guard let assessment = snapshot.assessment,
              seenAssessments.insert(assessment).inserted else { return }

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
                  snapshot.transcript.contains(evidence.quote) else {
                throw BackendAnalysisError.schema(detail: "Bukti analisis tidak sesuai transkrip.")
            }
            guard seenEvidence.insert(evidence).inserted else { continue }
            let line = TranscriptLine(
                id: nextLineID,
                offset: TimeInterval(nextLineID * 5),
                speaker: .unknown,
                text: evidence.quote,
                flagged: [evidence.quote],
                signals: evidenceSignals
            )
            nextLineID += 1
            continuation.yield(ChunkAssessment(line: line, level: level, signals: evidenceSignals))
        }
    }

    private func terminalError(from snapshot: SnapshotDTO) throws {
        guard ["running", "completed", "error"].contains(snapshot.status) else {
            throw BackendAnalysisError.schema(detail: "Status sesi backend tidak dikenal.")
        }
        if snapshot.status == "error" {
            guard let failure = snapshot.error else {
                throw BackendAnalysisError.schema(detail: "Sesi gagal tanpa keterangan.")
            }
            throw BackendAnalysisError.session(code: failure.code, detail: failure.message)
        }
    }

    private func riskLevel(_ value: String) throws -> RiskLevel {
        switch value {
        case "low": .safe
        case "needs_review": .review
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

    private func delete(_ id: String, from baseURL: URL) async {
        var request = URLRequest(url: endpoint(baseURL, "api", "demo", id))
        request.httpMethod = "DELETE"
        let session = session
        await Task.detached {
            _ = try? await session.data(for: request)
        }.value
    }

    private static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let detail = object["detail"] as? String { return detail }
        if let detail = object["detail"] as? [String: Any],
           let message = detail["message"] as? String { return message }
        return nil
    }

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.keyDecodingStrategy = .convertFromSnakeCase
        return value
    }()
}

private struct SnapshotDTO: Decodable, Sendable {
    let id: String
    let scenario: String
    let title: String
    let status: String
    let progress: Int
    let transcript: String
    let assessment: AssessmentDTO?
    let error: FailureDTO?
}

private struct AssessmentDTO: Decodable, Hashable, Sendable {
    let riskLevel: String
    let signals: [String]
    let evidence: [EvidenceDTO]
    let explanation: String
    let recommendedAction: String
}

private struct EvidenceDTO: Decodable, Hashable, Sendable {
    let quote: String
    let signals: [String]
}

private struct FailureDTO: Decodable, Sendable {
    let code: String
    let message: String
}
