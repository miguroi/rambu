import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct AppModelTests {
    private func makeModel(persona: Persona = .ratna) -> AppModel {
        AppModel(
            persona: persona,
            onboardingComplete: true,
            analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
            liveActivities: false,
            notifications: false,
            speech: false
        )
    }

    @Test("Telepon wajar tidak pernah dikirim ke pengawas")
    func safeCallIsNotRelayed() async {
        let model = makeModel()
        await model.startCall(.neighbourSafe).value

        #expect(model.alerts.isEmpty)
        #expect(model.session?.level == .safe)
        // Telepon aman tidak memunculkan push dan tidak masuk riwayat.
        #expect(model.toast == nil)
        let before = model.history.count
        model.endCall()
        #expect(model.history.count == before)
    }

    @Test("Orang tua menerima push Bahaya yang menyebut kedua pengawas")
    func parentGetsDangerPush() async throws {
        let model = makeModel()
        await model.startCall(.bankOTP).value

        let push = try #require(model.toast)
        #expect(push.level == .danger)
        #expect(push.title.hasPrefix("Bahaya"))
        #expect(push.body.contains("Sinta") && push.body.contains("Richard"))
    }

    @Test("Telepon penipuan sampai ke kedua pengawas beserta kalimat penelepon saja")
    func scamCallReachesBothGuardians() async throws {
        let model = makeModel()
        await model.startCall(.bankOTP).value

        let alert = try #require(model.alerts.first)
        #expect(alert.level == .danger)
        #expect(Set(alert.recipients) == [.sinta, .richard])
        #expect(!alert.evidence.isEmpty)
        #expect(alert.evidence.allSatisfy { $0.speaker == .caller && $0.isFlagged })
    }

    @Test("Keputusan pertama berlaku dan mengunci pengawas lain")
    func firstDecisionWins() async throws {
        let model = makeModel()
        await model.startCall(.bankOTP).value
        let id = try #require(model.alerts.first?.id)

        model.switchPersona(.sinta)
        guard case .accepted(let first) = model.decide(.scam, on: id) else {
            Issue.record("Keputusan Sinta seharusnya diterima")
            return
        }
        #expect(first.by == .sinta)

        model.switchPersona(.richard)
        let alert = try #require(model.alerts.first { $0.id == id })
        #expect(alert.decision?.by == .sinta)
        #expect(model.canDecide(alert) == false)

        guard case .alreadyDecided(let existing) = model.decide(.safe, on: id) else {
            Issue.record("Keputusan Richard seharusnya ditolak")
            return
        }
        #expect(existing.by == .sinta)
        #expect(existing.verdict == .scam)
    }

    @Test("Orang tua tidak bisa memberi keputusan untuk dirinya sendiri")
    func parentCannotDecide() async throws {
        let model = makeModel()
        await model.startCall(.bankOTP).value
        let id = try #require(model.alerts.first?.id)

        #expect(model.decide(.safe, on: id) == .unknownAlert)
        #expect(model.alerts.first?.decision == nil)
    }

    @Test("Keputusan yang masuk tersimpan di riwayat setelah telepon ditutup")
    func decisionIsKeptInHistory() async throws {
        let model = makeModel()
        await model.startCall(.accidentTransfer).value
        let id = try #require(model.alerts.first?.id)
        model.simulateDecision(by: .richard, .scam, on: id)
        model.endCall()

        let record = try #require(model.history.first { $0.id == id })
        #expect(record.decision?.by == .richard)
        #expect(record.level == .danger)
        #expect(model.session == nil)
    }

    @Test("Tingkat risiko tidak pernah turun selama satu panggilan")
    func levelIsMonotonic() async {
        for scenario in Scenario.all {
            let context = CallContext(id: UUID(), channel: scenario.channel, startedAt: .now, scenario: scenario)
            var levels: [RiskLevel] = []
            for await chunk in ScenarioAnalysis(interval: .zero, initialDelay: .zero).assessments(for: context) {
                levels.append(chunk.level)
            }
            #expect(levels == levels.sorted(), "Tingkat turun di skenario \(scenario.id)")
        }
    }

    @Test("Dua tanda berbeda langsung dianggap Bahaya")
    func riskRules() {
        #expect(RiskRules.level(for: []) == .safe)
        #expect(RiskRules.level(for: [.impersonation]) == .review)
        #expect(RiskRules.level(for: [.urgency]) == .review)
        #expect(RiskRules.level(for: [.secretCode]) == .danger)
        #expect(RiskRules.level(for: [.impersonation, .urgency]) == .danger)
    }

    // MARK: Fitur P0 sampai P2

    @Test("Data keluarga dan riwayat tersimpan di HP dan terbaca lagi")
    func stateSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rambu-\(UUID()).json")
        let store = LocalStore(url: url)
        defer { store.clear() }

        let first = AppModel(analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
                             liveActivities: false, notifications: false, speech: false, store: store)
        first.renameParent("Bu Sri")
        first.completeOnboarding(as: .ratna)
        await first.startCall(.bankOTP).value
        first.endCall()

        let second = AppModel(liveActivities: false, notifications: false, speech: false, store: store)
        #expect(second.onboardingComplete)
        #expect(second.parent.name == "Bu Sri")
        #expect(second.history.first?.level == .danger)
    }

    @Test("Tanpa jawaban pengawas, orang tua diminta menahan diri")
    func unansweredAlertEscalates() async throws {
        let model = AppModel(persona: .ratna, onboardingComplete: true,
                             analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
                             liveActivities: false, notifications: false, speech: false,
                             escalationDelay: .milliseconds(50))
        await model.startCall(.bankOTP).value
        try await Task.sleep(for: .milliseconds(200))

        let id = try #require(model.session?.id)
        #expect(model.unanswered.contains(id))
        #expect(model.toast?.title == "Belum ada jawaban")
        #expect(model.toast?.body.contains("Jangan lakukan tindakan apa pun dulu") == true)
    }

    @Test("Loudspeaker mati: Rambu mengingatkan dan baru mendengar setelah dinyalakan")
    func speakerReminder() async throws {
        let model = AppModel(persona: .ratna, onboardingComplete: true,
                             analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
                             liveActivities: false, notifications: false, speech: false,
                             speakerCheckDelay: .milliseconds(10))
        model.speakerOffNextCall = true
        await model.startCall(.bankOTP).value

        #expect(model.toast?.title == "Nyalakan loudspeaker")
        #expect(model.alerts.isEmpty)

        await model.turnOnSpeaker()?.value
        #expect(model.session?.speakerOn == true)
        #expect(model.alerts.first?.level == .danger)
    }

    @Test("Pengawas yang kalah cepat diberi tahu siapa yang menjawab lebih dulu")
    func lateGuardianIsTold() async throws {
        let model = makeModel()
        await model.startCall(.bankOTP).value
        let id = try #require(model.alerts.first?.id)
        model.simulateDecision(by: .richard, .scam, on: id)

        model.switchPersona(.sinta)
        let outcome = model.decide(.safe, on: id)
        #expect(outcome == .alreadyDecided(try #require(model.alerts.first?.decision)))
        #expect(model.toast?.title == "Richard sudah menjawab lebih dulu")
    }

    @Test("Tautan undangan dari WhatsApp mengisi kode pengawas")
    func inviteLinkFillsCode() {
        #expect(InviteLink.code(from: URL(string: "rambu://gabung?kode=482913")!) == "482913")
        #expect(InviteLink.code(from: InviteLink.url(code: "715204")) == "715204")
        #expect(InviteLink.code(from: URL(string: "rambu://gabung?kode=12")!) == nil)

        let model = AppModel(liveActivities: false, notifications: false, speech: false)
        model.handleIncoming(URL(string: "rambu://gabung?kode=482913")!)
        #expect(model.onboardingStep == .enterCode)
        #expect(model.pendingInviteCode == "482913")
    }

    @Test("Jawaban Aman tercatat sebagai umpan balik dan masuk ringkasan")
    func safeDecisionIsFeedback() async throws {
        let model = makeModel()
        await model.startCall(.courierApp).value
        let id = try #require(model.alerts.first?.id)
        model.switchPersona(.sinta)
        model.decide(.safe, on: id)
        model.switchPersona(.ratna)
        model.endCall()

        let feedback = try #require(model.feedback as? LocalDetectionFeedback)
        #expect(feedback.reported == [id])
        let record = try #require(model.history.first { $0.id == id })
        #expect(record.incidentSummary.contains("Sinta menandai aman"))
        #expect(record.incidentSummary.contains("menyuruh pasang aplikasi"))
    }

    @Test("Pengawas bisa menjaga lebih dari satu orang tua")
    func guardianProtectsSeveralParents() {
        let model = makeModel(persona: .sinta)
        let added = model.addProtectedParent(code: "715204")
        #expect(added?.name == "Pak Hadi")
        #expect(model.protectedParents.count == 2)
    }
}
