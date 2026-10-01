import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct CallViewModelTests {
    private func makeCall(
        analysis: any CallAnalysisSource = ScenarioAnalysis(interval: .zero, initialDelay: .zero),
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
            analysis: analysis,
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

    @Test("Semua kegagalan backend terlihat tanpa peringatan atau riwayat palsu")
    func backendFailuresAreVisibleAndDoNotCreateRisk() async throws {
        let failures: [BackendAnalysisError] = [
            .transport(detail: "Server http://10.0.0.8:8000 tidak dapat dihubungi."),
            .http(status: 503, detail: "Langflow belum siap."),
            .decoding,
            .schema(detail: "Bukti analisis tidak sesuai transkrip."),
            .session(code: "analysis_timeout", detail: "Langflow tidak merespons."),
        ]

        for error in failures {
            let source = CountingFailureSource(error: error)
            let (state, call) = makeCall(analysis: source)
            let historyCount = state.history.count

            await call.start(.bankOTP).value

            let session = try #require(state.session)
            let failure = try #require(session.analysisFailure)
            #expect(session.isListening == false)
            #expect(failure.code == error.code)
            #expect(failure.title == "Analisis panggilan gagal")
            #expect(state.toast?.title == failure.title)
            #expect(state.toast?.body == failure.detail)
            if case .http(let status, _) = error {
                #expect(failure.detail.contains("HTTP \(status)"))
            }
            #expect(state.alerts.isEmpty)

            call.end()
            #expect(state.history.count == historyCount)
        }
    }

    @Test("Mencoba lagi membuat sesi baru dan menghapus kegagalan lama")
    func retryStartsCleanSession() async throws {
        let source = CountingFailureSource(
            error: .transport(detail: "Server Rambu tidak dapat dihubungi.")
        )
        let (state, call) = makeCall(analysis: source)

        await call.start(.bankOTP).value
        let first = try #require(state.session)
        #expect(first.analysisFailure != nil)

        await call.start(.bankOTP).value
        let second = try #require(state.session)

        #expect(second.id != first.id)
        #expect(source.invocationCount == 2)
        #expect(second.analysisFailure?.code == "transport")
    }
}
