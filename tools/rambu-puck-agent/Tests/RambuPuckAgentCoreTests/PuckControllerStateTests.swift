import XCTest
@testable import RambuPuckAgentCore

final class PuckControllerStateTests: XCTestCase {
    func testPairStartListenWarnEndCompleteHappyPath() {
        var state = PuckControllerState.disconnected
        XCTAssertNil(PuckControllerReducer.reduce(state: &state, event: .paired))
        XCTAssertEqual(state, .ready)

        XCTAssertEqual(PuckControllerReducer.reduce(state: &state, event: .startTapped), .start)
        XCTAssertEqual(state, .starting)
        XCTAssertNil(PuckControllerReducer.reduce(
            state: &state,
            event: .engineState(.listening(sessionID: "session-1"))
        ))
        XCTAssertEqual(state, .listening(sessionID: "session-1"))

        let warning = PuckWarning(title: "Telepon mencurigakan", recommendedAction: "Hati-hati")
        XCTAssertNil(PuckControllerReducer.reduce(
            state: &state,
            event: .warning(severity: .needsReview, warning: warning)
        ))
        XCTAssertEqual(state, .warning(
            sessionID: "session-1",
            severity: .needsReview,
            warning: warning
        ))

        XCTAssertEqual(PuckControllerReducer.reduce(state: &state, event: .endTapped), .end)
        XCTAssertEqual(state, .ending(sessionID: "session-1"))
        XCTAssertNil(PuckControllerReducer.reduce(
            state: &state,
            event: .engineState(.completed(sessionID: "session-1"))
        ))
        XCTAssertEqual(state, .ready)
    }

    func testShortcutTogglesOnlyStableReadyAndListeningStates() {
        var ready = PuckControllerState.ready
        XCTAssertEqual(PuckControllerReducer.reduce(state: &ready, event: .shortcutToggled), .start)
        XCTAssertEqual(ready, .starting)

        var listening = PuckControllerState.listening(sessionID: "session-1")
        XCTAssertEqual(PuckControllerReducer.reduce(state: &listening, event: .shortcutToggled), .end)
        XCTAssertEqual(listening, .ending(sessionID: "session-1"))
    }

    func testDuplicateActionsAreSuppressedDuringStartingAndEnding() {
        var starting = PuckControllerState.starting
        XCTAssertNil(PuckControllerReducer.reduce(state: &starting, event: .startTapped))
        XCTAssertNil(PuckControllerReducer.reduce(state: &starting, event: .endTapped))
        XCTAssertNil(PuckControllerReducer.reduce(state: &starting, event: .shortcutToggled))
        XCTAssertEqual(starting, .starting)

        var ending = PuckControllerState.ending(sessionID: "session-1")
        XCTAssertNil(PuckControllerReducer.reduce(state: &ending, event: .startTapped))
        XCTAssertNil(PuckControllerReducer.reduce(state: &ending, event: .endTapped))
        XCTAssertNil(PuckControllerReducer.reduce(state: &ending, event: .shortcutToggled))
        XCTAssertEqual(ending, .ending(sessionID: "session-1"))
    }

    func testWarningsOnlyEscalateWhileListening() {
        let yellow = PuckWarning(title: "Periksa", recommendedAction: "Tanya")
        let red = PuckWarning(title: "Penipuan", recommendedAction: "Tutup")
        var state = PuckControllerState.listening(sessionID: "session-1")

        _ = PuckControllerReducer.reduce(
            state: &state,
            event: .warning(severity: .needsReview, warning: yellow)
        )
        _ = PuckControllerReducer.reduce(
            state: &state,
            event: .warning(severity: .low, warning: PuckWarning(title: "Aman", recommendedAction: ""))
        )
        XCTAssertEqual(state, .warning(
            sessionID: "session-1",
            severity: .needsReview,
            warning: yellow
        ))

        _ = PuckControllerReducer.reduce(
            state: &state,
            event: .warning(severity: .highRisk, warning: red)
        )
        XCTAssertEqual(state, .warning(
            sessionID: "session-1",
            severity: .highRisk,
            warning: red
        ))
    }

    func testRetryEndingIsExplicitAndDoesNotStartCapture() {
        var state = PuckControllerState.ending(sessionID: "session-1")
        _ = PuckControllerReducer.reduce(
            state: &state,
            event: .engineState(.retryEnding(sessionID: "session-1", message: "offline"))
        )
        XCTAssertEqual(state, .error(message: "offline", retryEndSessionID: "session-1"))

        XCTAssertEqual(PuckControllerReducer.reduce(state: &state, event: .retryTapped), .retryEnd)
        XCTAssertEqual(state, .ending(sessionID: "session-1"))
    }

    func testCredentialRemovalAndRePairResetToDisconnected() {
        var state = PuckControllerState.listening(sessionID: "session-1")
        XCTAssertEqual(PuckControllerReducer.reduce(state: &state, event: .rePairTapped), .clearCredential)
        XCTAssertEqual(state, .disconnected)

        state = .ready
        XCTAssertNil(PuckControllerReducer.reduce(state: &state, event: .credentialMissing))
        XCTAssertEqual(state, .disconnected)
        XCTAssertNil(PuckControllerReducer.reduce(state: &state, event: .shortcutToggled))
    }

    func testEngineFailureIsExposedWithoutClaimingCompletion() {
        var state = PuckControllerState.listening(sessionID: "session-1")
        _ = PuckControllerReducer.reduce(state: &state, event: .engineState(.error("microphone failed")))
        XCTAssertEqual(state, .error(message: "microphone failed", retryEndSessionID: nil))
    }
}
