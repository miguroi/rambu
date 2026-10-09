import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct OnboardingViewModelTests {
    @Test("Onboarding dan profil memakai AppState yang sama")
    func completesOnSharedState() {
        let state = AppState()
        let profile = ProfileViewModel(
            state: state,
            notifier: RambuNotifier(enabled: false),
            narrator: Narrator(enabled: false),
            network: NetworkMonitor(),
            store: nil
        )
        let onboarding = OnboardingViewModel(state: state, profile: profile)

        profile.renameParent("Bu Sri")
        onboarding.complete(as: .ratna)

        #expect(state.onboardingComplete)
        #expect(state.parent.name == "Bu Sri")
        #expect(state.puck == .unpaired)
        #expect(state.history.isEmpty)
        #expect(state.guardians.isEmpty)
    }

    @Test("Kode undangan mengarahkan onboarding pengawas")
    func guardianDraftUsesEnteredName() {
        let state = AppState(persona: .sinta)
        let profile = ProfileViewModel(state: state, notifier: RambuNotifier(enabled: false),
                                       narrator: Narrator(enabled: false), network: NetworkMonitor(), store: nil)
        profile.renameGuardian(.sinta, name: "Dewi", relation: "Anak")
        #expect(state.currentPerson.name == "Dewi")
        #expect(state.guardians.isEmpty)
    }

    @Test("Completing real setup preserves existing calls and server family members")
    func completingSetupPreservesRealData() {
        let state = AppState()
        let profile = ProfileViewModel(state: state, notifier: RambuNotifier(enabled: false),
                                       narrator: Narrator(enabled: false), network: NetworkMonitor(), store: nil)
        let record = CallRecord(id: UUID(), title: "Panggilan", callerDetail: "Kontak", channel: .whatsapp,
                                startedAt: .now, duration: 60, level: .safe, signals: [], evidence: [], decision: nil)
        state.history = [record]
        state.guardians = [Person(id: "real-child", name: "Dewi", initial: "D", relation: "Anak", colorHex: 0x006F63)]
        OnboardingViewModel(state: state, profile: profile).complete(as: .ratna)
        #expect(state.history == [record])
        #expect(state.guardians.map(\.name) == ["Dewi"])
        #expect(!state.puck.isConnected)
    }

    @Test("Kode undangan mengarahkan onboarding pengawas")
    func inviteCodeSelectsGuardianFlow() {
        let state = AppState()
        let profile = ProfileViewModel(
            state: state,
            notifier: RambuNotifier(enabled: false),
            narrator: Narrator(enabled: false),
            network: NetworkMonitor(),
            store: nil
        )
        let onboarding = OnboardingViewModel(state: state, profile: profile)

        onboarding.handleInvite(code: "482913")

        #expect(state.pendingInviteCode == "482913")
        #expect(state.onboardingStep == .guardianProfile)
        #expect(!state.persona.isParent)
    }
}
