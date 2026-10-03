import Foundation
import XCTest
@testable import RambuPuckAgentCore

actor ScriptedTransport {
    private var results: [Result<(Data, HTTPURLResponse), Error>]
    private(set) var requests: [URLRequest] = []

    init(results: [Result<(Data, HTTPURLResponse), Error>]) {
        self.results = results
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try results.removeFirst().get()
    }
}

final class PuckAPITests: XCTestCase {
    func testPairDecodesBackendResponseWithIdentifierKeys() async throws {
        let body = Data(
            #"{"puck_id":"puck-1","family_id":"family-1","display_name":"Mac puck","access_token":"secret-token"}"#.utf8
        )
        let transport = ScriptedTransport(results: [.success((body, response(status: 201)))])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: nil,
            retryDelaysNanoseconds: [],
            transport: { request in try await transport.send(request) }
        )

        let puck = try await api.pair(code: "730328", displayName: "Mac puck")

        XCTAssertEqual(puck.puckID, "puck-1")
        XCTAssertEqual(puck.familyID, "family-1")
        XCTAssertEqual(puck.displayName, "Mac puck")
        XCTAssertEqual(puck.accessToken, "secret-token")
    }

    func testUploadSendsBearerSequenceFinalAndWaveHeaders() async throws {
        let body = sessionJSON(id: "session-1", status: "listening")
        let transport = ScriptedTransport(results: [.success((body, response(status: 200)))])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: "puck-secret",
            retryDelaysNanoseconds: [],
            transport: { request in try await transport.send(request) }
        )

        _ = try await api.uploadChunk(
            sessionID: "session-1", sequence: 4, final: true, wav: Data([1, 2])
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/pucks/sessions/session-1/chunks")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer puck-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rambu-Sequence"), "4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rambu-Final"), "true")
    }

    func testUploadDecodesRiskAssessmentForLocalWarning() async throws {
        let body = Data(
            #"{"id":"session-1","call_id":"7f011753-8f09-4a45-8812-8a4591a96b3c","channel":null,"status":"listening","puck_connected":true,"masked_transcript":"Halo","assessment":{"risk_level":"high_risk","signals":["secret_code","transfer"],"evidence":[],"explanation":"Permintaan kode dan transfer.","recommended_action":"Tutup telepon sekarang."},"outcome":null,"end_requested":false,"revision":1,"next_sequence":1,"started_at":"2026-10-01T10:00:00Z","end_requested_at":null,"ended_at":null,"failure":null}"#.utf8
        )
        let transport = ScriptedTransport(results: [.success((body, response(status: 200)))])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: "puck-secret",
            retryDelaysNanoseconds: [],
            transport: { request in try await transport.send(request) }
        )

        let session = try await api.uploadChunk(
            sessionID: "session-1", sequence: 0, final: false, wav: Data([1, 2])
        )

        XCTAssertEqual(session.assessment?.riskLevel, .highRisk)
        XCTAssertEqual(session.assessment?.recommendedAction, "Tutup telepon sekarang.")
    }

    func testWarningGateWarnsOncePerRiskEscalation() {
        var gate = PuckWarningGate()
        let review = PuckAssessment(
            riskLevel: .needsReview,
            recommendedAction: "Verifikasi penelepon."
        )
        let danger = PuckAssessment(
            riskLevel: .highRisk,
            recommendedAction: "Tutup telepon sekarang."
        )

        XCTAssertNil(gate.warning(for: nil))
        XCTAssertEqual(gate.warning(for: review)?.title, "Telepon mencurigakan")
        XCTAssertNil(gate.warning(for: review))
        XCTAssertEqual(gate.warning(for: danger)?.title, "Terindikasi penipuan")
        XCTAssertNil(gate.warning(for: danger))
    }

    func testRetriesTransportAndServerFailuresThenReturnsSuccess() async throws {
        let transport = ScriptedTransport(results: [
            .failure(URLError(.cannotConnectToHost)),
            .success((Data("server unavailable".utf8), response(status: 503))),
            .success((sessionJSON(id: "session-1", status: "listening"), response(status: 200))),
        ])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: "puck-secret",
            retryDelaysNanoseconds: [0, 0],
            transport: { request in try await transport.send(request) }
        )

        let session = try await api.activeSession()

        XCTAssertEqual(session?.id, "session-1")
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 3)
    }

    func testAuthenticationFailureDoesNotRetryAndPreservesServerDetail() async throws {
        let detail = Data(#"{"detail":"Token puck tidak valid."}"#.utf8)
        let transport = ScriptedTransport(results: [
            .success((detail, response(status: 401))),
            .success((sessionJSON(id: "should-not-run", status: "listening"), response(status: 200))),
        ])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: "wrong",
            retryDelaysNanoseconds: [0, 0],
            transport: { request in try await transport.send(request) }
        )

        do {
            _ = try await api.activeSession()
            XCTFail("Expected authentication failure")
        } catch let error as PuckAPIError {
            XCTAssertEqual(error.description, "HTTP 401: Token puck tidak valid.")
        }
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testActiveSessionTreats404AsNoCurrentCall() async throws {
        let transport = ScriptedTransport(results: [
            .success((Data(#"{"detail":"Tidak ada sesi perlindungan aktif."}"#.utf8), response(status: 404)))
        ])
        let api = PuckAPI(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            token: "puck-secret",
            retryDelaysNanoseconds: [],
            transport: { request in try await transport.send(request) }
        )

        let session = try await api.activeSession()
        XCTAssertNil(session)
    }

    func testConfigurationRequiresServerAndListenToken() throws {
        XCTAssertThrowsError(
            try AgentConfiguration(environment: [:], command: .pair)
        )
        XCTAssertThrowsError(
            try AgentConfiguration(
                environment: ["RAMBU_SERVER_URL": "http://127.0.0.1:8000"],
                command: .listen
            )
        )

        let pair = try AgentConfiguration(
            environment: ["RAMBU_SERVER_URL": "http://127.0.0.1:8000"],
            command: .pair
        )
        XCTAssertNil(pair.puckToken)
    }

    private func sessionJSON(id: String, status: String) -> Data {
        Data(
            """
            {"id":"\(id)","call_id":"7f011753-8f09-4a45-8812-8a4591a96b3c",\
            "channel":null,"status":"\(status)","puck_connected":true,\
            "masked_transcript":"","assessment":null,"outcome":null,\
            "end_requested":false,"revision":1,"next_sequence":0,\
            "started_at":"2026-10-01T10:00:00Z","end_requested_at":null,\
            "ended_at":null,"failure":null}
            """.utf8
        )
    }

    private func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
