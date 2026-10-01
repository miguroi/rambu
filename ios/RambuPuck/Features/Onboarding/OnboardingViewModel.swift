import Observation

/// Mengelola perpindahan dan penyelesaian alur onboarding.
@MainActor
@Observable
final class OnboardingViewModel {
    @ObservationIgnored let state: AppState
    @ObservationIgnored private let profile: ProfileViewModel

    init(state: AppState, profile: ProfileViewModel) {
        self.state = state
        self.profile = profile
    }

    func complete(as persona: Persona) {
        state.persona = persona
        state.puck = .demo
        state.history = CallRecord.seed(decider: state.person(for: .richard))
        state.onboardingComplete = true
        state.onboardingStep = .welcome
        state.pendingInviteCode = nil
        profile.persist()
    }

    func handleInvite(code: String) {
        state.pendingInviteCode = code
        state.onboardingStep = .enterCode
    }
}
