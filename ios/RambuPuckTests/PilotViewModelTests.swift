import Foundation
import Testing
@testable import RambuPuck

private actor PilotHTTPStub: HTTPDataSession {
    private let responses: [String: Data]
    private var requestedPaths: [String] = []

    init(responses: [String: String]) {
        self.responses = responses.mapValues { Data($0.utf8) }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        requestedPaths.append(path)
        guard let data = responses[path], let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    func paths() -> [String] { requestedPaths }
}

@MainActor
struct PilotViewModelTests {
    @Test("Respons buat keluarga membaca family_id dari backend")
    func decodesCreateFamilyResponse() throws {
        let data = Data(#"""
        {
          "family_id": "family-1",
          "member": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
          "access_token": "token-1",
          "invite_code": "123456",
          "invite_expires_at": null
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let session = try decoder.decode(PilotSessionDTO.self, from: data)

        #expect(session.familyID == "family-1")
        #expect(session.inviteCode == "123456")
    }

    @Test("Respons profil keluarga membaca family_id dari backend")
    func decodesFamilyProfileResponse() throws {
        let data = Data(#"""
        {
          "family_id": "family-1",
          "member": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
          "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
          "guardians": []
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let profile = try decoder.decode(PilotProfileDTO.self, from: data)

        #expect(profile.familyID == "family-1")
    }

    @Test("Riwayat pilot membaca semua hasil penilaian backend")
    func decodesEveryHistoryPresentation() throws {
        let data = Data(#"""
        [
          {
            "id": "10000000-0000-0000-0000-000000000001",
            "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
            "title": "Aman", "caller_detail": "Nomor tidak tersedia", "channel": "cellular",
            "started_at": "2026-10-03T10:00:00Z", "ended_at": "2026-10-03T10:00:45Z",
            "duration_seconds": 45, "outcome": "analyzed", "presentation": "safe",
            "signals": [], "evidence": [], "decision": null, "failure": null
          },
          {
            "id": "10000000-0000-0000-0000-000000000002",
            "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
            "title": "Waspada", "caller_detail": "+62 812-••••-4417", "channel": "whatsapp",
            "started_at": "2026-10-03T10:01:00Z", "ended_at": "2026-10-03T10:01:45Z",
            "duration_seconds": 45, "outcome": "analyzed", "presentation": "review",
            "signals": ["impersonation"], "evidence": [], "decision": null, "failure": null
          },
          {
            "id": "10000000-0000-0000-0000-000000000003",
            "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
            "title": "Bahaya", "caller_detail": "+62 812-••••-4417", "channel": "cellular",
            "started_at": "2026-10-03T10:02:00Z", "ended_at": "2026-10-03T10:02:45Z",
            "duration_seconds": 45, "outcome": "analyzed", "presentation": "danger",
            "signals": ["secretCode", "remoteApp"],
            "evidence": [{"id": 0, "offset": 0, "speaker": "unknown", "text": "Berikan OTP", "flagged": ["OTP"], "signals": ["secretCode"]}],
            "decision": null, "failure": null
          },
          {
            "id": "10000000-0000-0000-0000-000000000004",
            "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
            "title": "Tidak terdengar", "caller_detail": "Nomor tidak tersedia", "channel": null,
            "started_at": "2026-10-03T10:03:00Z", "ended_at": "2026-10-03T10:03:45Z",
            "duration_seconds": 45, "outcome": "no_speech", "presentation": "unassessed",
            "signals": [], "evidence": [], "decision": null, "failure": null
          },
          {
            "id": "10000000-0000-0000-0000-000000000005",
            "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
            "title": "Gagal", "caller_detail": "Nomor tidak tersedia", "channel": "cellular",
            "started_at": "2026-10-03T10:04:00Z", "ended_at": "2026-10-03T10:04:45Z",
            "duration_seconds": 45, "outcome": "error", "presentation": "unassessed",
            "signals": [], "evidence": [], "decision": null,
            "failure": {"code": "analysis_timeout", "message": "Analisis panggilan gagal."}
          }
        ]
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let records = try decoder.decode([PilotHistoryRecordDTO].self, from: data)

        #expect(records.map(\.presentation) == ["safe", "review", "danger", "unassessed", "unassessed"])
        #expect(records.map(\.outcome) == ["analyzed", "analyzed", "analyzed", "no_speech", "error"])
        #expect(records[2].signals == ["secretCode", "remoteApp"])
        #expect(records[2].evidence[0].line.signals == [.secretCode])
        #expect(records[4].failure?.code == "analysis_timeout")
    }

    @Test("Refresh menerapkan profil, alert, dan riwayat secara atomik")
    func testRefreshFetchesProfileAlertsAndHistoryBeforeCallbacks() async {
        let stub = PilotHTTPStub(responses: [
            "/api/pilot/profile": Self.profileJSON,
            "/api/pilot/alerts": "[]",
            "/api/pilot/history": "[]",
        ])
        let sync = PilotSync(session: stub, initialCredentials: Self.credentials)
        var callbacks: [String] = []
        sync.onProfile = { _ in callbacks.append("profile") }
        sync.onAlerts = { _ in callbacks.append("alerts") }
        sync.onHistory = { _ in callbacks.append("history") }

        await sync.refresh()

        #expect(callbacks == ["profile", "alerts", "history"])
        #expect(Set(await stub.paths()) == [
            "/api/pilot/profile", "/api/pilot/alerts", "/api/pilot/history",
        ])
    }

    @Test("Riwayat rusak tidak menerapkan sebagian hasil refresh")
    func testRefreshIsAtomicWhenHistoryDecodingFails() async {
        let stub = PilotHTTPStub(responses: [
            "/api/pilot/profile": Self.profileJSON,
            "/api/pilot/alerts": "[]",
            "/api/pilot/history": #"[{"id":"not-a-uuid"}]"#,
        ])
        let sync = PilotSync(session: stub, initialCredentials: Self.credentials)
        var callbackCount = 0
        var visibleHistory = ["existing-call"]
        var receivedError: String?
        sync.onProfile = { _ in callbackCount += 1 }
        sync.onAlerts = { _ in callbackCount += 1 }
        sync.onHistory = { records in
            callbackCount += 1
            visibleHistory = records.map(\.title)
        }
        sync.onError = { receivedError = $0 }

        await sync.refresh()

        #expect(callbackCount == 0)
        #expect(visibleHistory == ["existing-call"])
        #expect(receivedError != nil)
    }

    private static let credentials = PilotCredentials(
        serverURL: "https://rambu.test",
        familyID: "family-1",
        member: PilotPersonDTO(id: "guardian-1", name: "Richard", relation: "Anak", role: "guardian"),
        accessToken: "test-token",
        inviteCode: nil
    )

    private static let profileJSON = #"""
    {
      "family_id": "family-1",
      "member": {"id": "guardian-1", "name": "Richard", "relation": "Anak", "role": "guardian"},
      "parent": {"id": "parent-1", "name": "Ratna", "relation": "Orang tua", "role": "parent"},
      "guardians": [{"id": "guardian-1", "name": "Richard", "relation": "Anak", "role": "guardian"}]
    }
    """#

    private func makePilot(persona: Persona = .ratna) -> (AppState, PilotViewModel) {
        let state = AppState(persona: persona, onboardingComplete: true)
        let profile = ProfileViewModel(
            state: state,
            notifier: RambuNotifier(enabled: false),
            narrator: Narrator(enabled: false),
            network: NetworkMonitor(),
            store: nil
        )
        let family = FamilyViewModel(
            state: state,
            relay: LocalFamilyRelay(),
            feedback: LocalDetectionFeedback(),
            liveActivity: CallLiveActivity(enabled: false),
            profile: profile,
            present: profile.present
        )
        return (state, PilotViewModel(state: state, pilot: nil, family: family, profile: profile))
    }

    @Test("Profil pilot memilih persona dan mengurutkan pengawas aktif")
    func appliesRemoteProfile() {
        let (state, pilot) = makePilot()
        let parent = PilotPersonDTO(id: "parent", name: "Bu Sri", relation: "Ibu", role: "parent")
        let sinta = PilotPersonDTO(id: "sinta", name: "Sinta", relation: "Anak", role: "guardian")
        let richard = PilotPersonDTO(id: "richard", name: "Richard", relation: "Anak", role: "guardian")

        pilot.applyProfile(PilotProfileDTO(
            familyID: "family",
            member: richard,
            parent: parent,
            guardians: [sinta, richard]
        ))

        #expect(state.persona == .sinta)
        #expect(state.parent.name == "Bu Sri")
        #expect(state.guardians.first?.id == "richard")
        #expect(state.pilotRole == "guardian")
    }

    @Test("Alert pilot yang sudah selesai masuk riwayat tanpa notifikasi baru")
    func endedRemoteAlertDoesNotNotifyAgain() {
        let (state, pilot) = makePilot(persona: .sinta)
        var alert = FamilyAlert(
            id: UUID(),
            parent: .ratna,
            callerDetail: "Nomor tidak dikenal",
            channel: .cellular,
            startedAt: .now,
            raisedAt: .now,
            level: .danger,
            signals: [.secretCode],
            evidence: [],
            recipients: Person.guardians,
            decision: nil
        )
        alert.callEnded = true

        pilot.applyAlerts([alert])

        #expect(state.history.contains { $0.id == alert.id })
        #expect(state.toast == nil)
    }
}
