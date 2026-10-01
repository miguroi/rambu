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
        #expect(state.puck == .demo)
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
        #expect(state.onboardingStep == .enterCode)
    }
}
