import Testing
@testable import RambuPuck

@MainActor
struct AppViewModelTests {
    @Test("Semua feature ViewModel memakai satu AppState")
    func composesOneSharedState() {
        let app = AppViewModel(
            onboardingComplete: true,
            liveActivities: false,
            notifications: false,
            speech: false,
            pilot: nil
        )

        #expect(app.onboarding.state === app.state)
        #expect(app.call.state === app.state)
        #expect(app.family.state === app.state)
        #expect(app.profile.state === app.state)
        #expect(app.pilot.state === app.state)
    }
}
