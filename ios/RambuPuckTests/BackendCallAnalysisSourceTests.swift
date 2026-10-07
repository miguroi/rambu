import Foundation
import Testing
@testable import RambuPuck

private enum StubTransportError: Error {
    case offline
}

private actor StubHTTPSession: HTTPDataSession {
    enum Stub: Sendable {
        case response(Data, Int)
        case failure
    }

    private let stubs: [Stub]
    private var index = 0
    private var recorded: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.append(request)
        if request.httpMethod == "DELETE" {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        }
        guard !stubs.isEmpty else { throw StubTransportError.offline }
        let stub = stubs[min(index, stubs.count - 1)]
        index += 1
        switch stub {
        case .response(let data, let status):
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .failure:
            throw StubTransportError.offline
        }
    }

    func requests() -> [URLRequest] { recorded }
}

@MainActor
struct BackendCallAnalysisSourceTests {
    private func context(scenario: Scenario? = .bankOTP) -> CallContext {
        CallContext(
            id: UUID(),
            metadata: scenario?.callMetadata ?? .production,
            startedAt: .now
        )
    }

    private func data(
        status: String,
        transcript: String = "",
        assessment: [String: Any]? = nil,
        error: [String: Any]? = nil
    ) throws -> Data {
        var value: [String: Any] = [
            "id": "session-1",
            "scenario": "bank-otp",
            "title": "Mengaku petugas bank",
            "status": status,
            "progress": status == "completed" ? 100 : 50,
            "transcript": transcript,
            "assessment": assessment as Any,
            "error": error as Any,
        ]
        if assessment == nil { value["assessment"] = NSNull() }
        if error == nil { value["error"] = NSNull() }
        return try JSONSerialization.data(withJSONObject: value)
    }

    private func assessment(
        risk: String,
        signals: [String],
        evidence: [[String: Any]]
    ) -> [String: Any] {
        [
            "risk_level": risk,
            "signals": signals,
            "evidence": evidence,
            "explanation": "Penjelasan berdasarkan percakapan.",
            "recommended_action": "Jangan berikan data.",
        ]
    }

    private func collect(
        _ source: BackendCallAnalysisSource,
        context: CallContext? = nil
    ) async throws -> [ChunkAssessment] {
        var result: [ChunkAssessment] = []
        for try await chunk in source.assessments(for: context ?? self.context()) {
            result.append(chunk)
        }
        return result
    }

    private func expectError(
        _ source: BackendCallAnalysisSource,
        context: CallContext? = nil
    ) async -> BackendAnalysisError? {
        do {
            _ = try await collect(source, context: context)
            Issue.record("Analysis should have failed")
            return nil
        } catch let error as BackendAnalysisError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    @Test("Polling maps exact enums and emits each evidence quote once")
    func mapsAndDeduplicatesAssessments() async throws {
        let review = assessment(
            risk: "needs_review",
            signals: ["impersonation"],
            evidence: [["quote": "Saya dari bank.", "signals": ["impersonation"]]]
        )
        let danger = assessment(
            risk: "high_risk",
            signals: ["impersonation", "secret_code"],
            evidence: [
                ["quote": "Saya dari bank.", "signals": ["impersonation"]],
                ["quote": "berikan OTP [KODE]", "signals": ["secret_code"]],
            ]
        )
        let transcript = "Saya dari bank. Tolong berikan OTP [KODE] sekarang."
        let session = StubHTTPSession([
            .response(try data(status: "running", transcript: transcript, assessment: review), 201),
            .response(try data(status: "running", transcript: transcript, assessment: review), 200),
            .response(try data(status: "running", transcript: transcript, assessment: danger), 200),
            .response(try data(status: "completed", transcript: transcript, assessment: danger), 200),
        ])
        let source = BackendCallAnalysisSource(
            serverURL: "http://127.0.0.1:8000",
            session: session,
            pollInterval: .zero
        )

        let chunks = try await collect(source)

        #expect(chunks.count == 2)
        #expect(chunks[0].level == .review)
        #expect(chunks[0].signals == [.impersonation])
        #expect(chunks[0].line.text == "Saya dari bank.")
        #expect(chunks[0].line.speaker == .unknown)
        #expect(chunks[1].level == .danger)
        #expect(chunks[1].signals == [.secretCode])
        #expect(chunks[1].line.text == "berikan OTP [KODE]")
        let requests = await session.requests()
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url?.path == "/api/demo/bank-otp")
        #expect(requests.filter { $0.httpMethod == "DELETE" }.count == 1)
    }

    @Test("Unknown signal fails schema validation")
    func rejectsUnknownSignal() async throws {
        let invalid = assessment(
            risk: "high_risk",
            signals: ["cryptocurrency"],
            evidence: [["quote": "kirim kripto", "signals": ["cryptocurrency"]]]
        )
        let session = StubHTTPSession([
            .response(try data(status: "completed", transcript: "kirim kripto", assessment: invalid), 201)
        ])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "schema")
    }

    @Test("Evidence must be an exact transcript substring")
    func rejectsInventedEvidence() async throws {
        let invalid = assessment(
            risk: "high_risk",
            signals: ["secret_code"],
            evidence: [["quote": "kutipan palsu", "signals": ["secret_code"]]]
        )
        let session = StubHTTPSession([
            .response(try data(status: "completed", transcript: "berikan OTP [KODE]", assessment: invalid), 201)
        ])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "schema")
    }

    @Test("Backend terminal error preserves its safe code and detail")
    func reportsBackendSessionFailure() async throws {
        let session = StubHTTPSession([
            .response(
                try data(
                    status: "error",
                    error: ["code": "analysis_timeout", "message": "Langflow tidak merespons."]
                ),
                201
            )
        ])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "analysis_timeout")
        #expect(error?.detail == "Langflow tidak merespons.")
    }

    @Test("HTTP failure preserves status and server detail")
    func reportsHTTPFailure() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["detail": "Skenario tidak ditemukan."])
        let session = StubHTTPSession([.response(body, 404)])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "http_404")
        #expect(error?.detail == "Skenario tidak ditemukan.")
    }

    @Test("Malformed JSON is a decoding failure")
    func reportsMalformedJSON() async {
        let session = StubHTTPSession([.response(Data("not-json".utf8), 201)])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "decoding")
    }

    @Test("Transport failure is not converted into an assessment")
    func reportsTransportFailure() async {
        let session = StubHTTPSession([.failure])

        let error = await expectError(BackendCallAnalysisSource(serverURL: "http://server.test", session: session))

        #expect(error?.code == "transport")
    }

    @Test("Invalid server and missing scenario fail during stream consumption")
    func rejectsInvalidInputs() async {
        let session = StubHTTPSession([])
        let invalidURL = await expectError(
            BackendCallAnalysisSource(serverURL: "not a server", session: session)
        )
        let missingScenario = await expectError(
            BackendCallAnalysisSource(serverURL: "http://server.test", session: session),
            context: context(scenario: nil)
        )

        #expect(invalidURL?.code == "invalid_server_url")
        #expect(missingScenario?.code == "invalid_scenario")
    }

    @Test("Cancelling polling deletes the remote session exactly once")
    func cancellationDeletesSession() async throws {
        let running = try data(status: "running")
        let session = StubHTTPSession([.response(running, 201), .response(running, 200)])
        let source = BackendCallAnalysisSource(
            serverURL: "http://server.test",
            session: session,
            pollInterval: .milliseconds(5)
        )
        let task = Task {
            try await collect(source)
        }

        for _ in 0..<100 {
            if await session.requests().count >= 2 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        task.cancel()
        _ = await task.result
        for _ in 0..<100 {
            if await session.requests().contains(where: { $0.httpMethod == "DELETE" }) { break }
            try await Task.sleep(for: .milliseconds(2))
        }

        let deletes = await session.requests().filter { $0.httpMethod == "DELETE" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.url?.path == "/api/demo/session-1")
    }
}
