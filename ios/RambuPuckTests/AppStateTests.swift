import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct AppStateTests {
    @Test("State bersama menghitung data tampilan dari satu sumber")
    func derivesSharedPresentationState() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AppState(persona: .sinta, onboardingComplete: true, now: now)
        let extraParent = Person(id: "hadi", name: "Pak Hadi", initial: "H", relation: "Ayah", colorHex: 0x8A5A12)
        state.extraParents = [extraParent]

        let session = CallSession(id: UUID(), scenario: .bankOTP, startedAt: now)
        state.session = session
        state.alerts = [FamilyAlert(
            id: session.id,
            parent: .ratna,
            callerDetail: "Nomor tidak dikenal",
            channel: .cellular,
            startedAt: now,
            raisedAt: now,
            level: .danger,
            signals: [.secretCode],
            evidence: [],
            recipients: Person.guardians,
            decision: nil
        )]

        #expect(state.currentPerson == .sinta)
        #expect(state.protectedParents == [.ratna, extraParent])
        #expect(state.activeAlert?.id == session.id)
        #expect(state.featuredAlert?.id == session.id)
        #expect(state.otherGuardians(than: .sinta) == [.richard])

        state.persona = .ratna
        state.notificationsAuthorized = false
        state.isOnline = false
        state.bluetoothOn = false
        #expect(state.issues == [.notificationsOff, .offline, .bluetoothOff])
    }

    @Test("SavedState pulih tanpa mengubah skema atau nilai")
    func restoresExistingSavedState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let renamedParent = Person.ratna.renamed("Bu Sri")
        let extraParent = Person(id: "hadi", name: "Pak Hadi", initial: "H", relation: "Ayah", colorHex: 0x8A5A12)
        let saved = SavedState(
            onboardingComplete: true,
            persona: .richard,
            parent: renamedParent,
            guardians: [.sinta, .richard],
            extraParents: [extraParent],
            history: CallRecord.seed(now: now),
            puck: .demo,
            narrationEnabled: false
        )

        let state = AppState(persona: .ratna, onboardingComplete: false, now: now)
        state.restore(saved)

        #expect(state.savedState == saved)
    }

    @Test("Protection presentation represents every production session state")
    func protectionPresentationStates() {
        let state = AppState(persona: .ratna, onboardingComplete: true)
        #expect(state.allowsDemoControls == false)
        #expect(state.protectionPresentation == .setupRequired)

        state.pilotConnected = true
        state.pilotRole = "parent"
        #expect(state.protectionPresentation == .monitoring)

        var session = CallSession(id: UUID(), metadata: .production, startedAt: .now)
        state.session = session
        #expect(state.protectionPresentation == .waitingForPuck)

        session.protectionStatus = .listening
        state.session = session
        #expect(state.protectionPresentation == .listening)

        let failure = AnalysisFailure(
            code: "analysis_timeout",
            title: "Analisis panggilan gagal",
            detail: "Langflow tidak merespons.",
            at: .now
        )
        session.analysisFailure = failure
        state.session = session
        #expect(state.protectionPresentation == .failed(failure))

        session.analysisFailure = nil
        session.protectionStatus = .completed
        session.level = .review
        state.session = session
        #expect(state.protectionPresentation == .completed(.review))

        session.protectionStatus = .noSpeech
        state.session = session
        #expect(state.protectionPresentation == .noSpeech)
    }
}
