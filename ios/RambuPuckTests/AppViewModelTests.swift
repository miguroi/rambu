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

    @Test("Komposisi normal memakai sesi proteksi produksi")
    func normalLaunchUsesProtectionAnalysis() {
        let source = DemoLaunch.productionAnalysis {
            ProtectionConnection(serverURL: "http://192.168.1.8:8000", accessToken: "parent-token")
        }

        #expect(source is ProtectionCallAnalysisSource)
    }

    @Test("Komposisi screenshot tetap memakai sumber fixture deterministik")
    func screenshotLaunchUsesFixtureAnalysis() throws {
        let source = try #require(DemoLaunch.analysisSource(serverURL: "http://192.168.1.8:8000") as? BackendCallAnalysisSource)

        #expect(source.serverURL == "http://192.168.1.8:8000")
    }
}
