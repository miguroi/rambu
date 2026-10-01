import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct CallViewModelTests {
    private func makeCall(
        escalationDelay: Duration = .seconds(60),
        speakerCheckDelay: Duration = .seconds(3)
    ) -> (AppState, CallViewModel) {
        let state = AppState(onboardingComplete: true)
        let profile = ProfileViewModel(
            state: state,
            notifier: RambuNotifier(enabled: false),
            narrator: Narrator(enabled: false),
            network: NetworkMonitor(),
            store: nil
        )
        let activity = CallLiveActivity(enabled: false)
        let family = FamilyViewModel(
            state: state,
            relay: LocalFamilyRelay(),
            feedback: LocalDetectionFeedback(),
            liveActivity: activity,
            profile: profile,
            present: profile.present
        )
        let pilot = PilotViewModel(state: state, pilot: nil, family: family, profile: profile)
        let call = CallViewModel(
            state: state,
            analysis: ScenarioAnalysis(interval: .zero, initialDelay: .zero),
            family: family,
            pilot: pilot,
            profile: profile,
            liveActivity: activity,
            escalationDelay: escalationDelay,
            speakerCheckDelay: speakerCheckDelay
        )
        return (state, call)
    }

    @Test("CallViewModel meneruskan telepon berbahaya ke keluarga")
    func dangerousCallPublishesAlert() async throws {
        let (state, call) = makeCall()

        await call.start(.bankOTP).value

        #expect(state.session?.level == .danger)
        #expect(try #require(state.alerts.first).level == .danger)
        #expect(state.toast?.title.hasPrefix("Bahaya") == true)
    }

    @Test("Mengakhiri telepon membatalkan pengingat dan eskalasi lama")
    func endingCallCancelsDelayedTasks() async {
        let (state, call) = makeCall(
            escalationDelay: .milliseconds(40),
            speakerCheckDelay: .milliseconds(40)
        )
        state.speakerOffNextCall = true
        let delayedSpeaker = call.start(.bankOTP)

        call.end()
        await delayedSpeaker.value
        try? await Task.sleep(for: .milliseconds(100))

        #expect(state.session == nil)
        #expect(state.toast == nil)
        #expect(state.unanswered.isEmpty)
    }
}
