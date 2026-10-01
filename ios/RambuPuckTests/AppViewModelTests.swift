import Testing
@testable import RambuPuck

@MainActor
struct AppViewModelTests {
    @Test("Semua feature ViewModel memakai satu AppState")
    func composesOneSharedState() {
        let app = AppViewModel(
            onboardingComplete: true,
            analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
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

    @Test("Komposisi aplikasi selalu memakai sumber analisis backend")
    func demoLaunchUsesBackendAnalysis() throws {
        let source = try #require(
            DemoLaunch.analysisSource(serverURL: "http://192.168.1.8:8000")
                as? BackendCallAnalysisSource
        )

        #expect(source.serverURL == "http://192.168.1.8:8000")
    }
}
