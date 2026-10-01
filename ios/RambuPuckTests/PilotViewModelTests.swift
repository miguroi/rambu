import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct PilotViewModelTests {
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
