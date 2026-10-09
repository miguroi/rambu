public enum PuckControllerState: Equatable, Sendable {
    case disconnected
    case ready
    case starting
    case listening(sessionID: String)
    case ending(sessionID: String)
    case warning(sessionID: String, severity: PuckRiskLevel, warning: PuckWarning)
    case error(message: String, retryEndSessionID: String?)
}

public enum PuckControllerEvent: Equatable, Sendable {
    case paired
    case credentialMissing
    case startTapped
    case endTapped
    case shortcutToggled
    case retryTapped
    case rePairTapped
    case engineState(PuckProtectionState)
    case warning(severity: PuckRiskLevel, warning: PuckWarning)
}

public enum PuckControllerEffect: Equatable, Sendable {
    case start
    case end
    case retryEnd
    case clearCredential
}

public enum PuckControllerReducer {
    @discardableResult
    public static func reduce(
        state: inout PuckControllerState,
        event: PuckControllerEvent
    ) -> PuckControllerEffect? {
        switch event {
        case .paired:
            state = .ready

        case .credentialMissing:
            state = .disconnected

        case .rePairTapped:
            state = .disconnected
            return .clearCredential

        case .startTapped:
            guard state == .ready else { return nil }
            state = .starting
            return .start

        case .endTapped:
            return beginEndingIfPossible(state: &state)

        case .shortcutToggled:
            if state == .ready {
                state = .starting
                return .start
            }
            return beginEndingIfPossible(state: &state)

        case .retryTapped:
            guard case .error(_, let sessionID?) = state else { return nil }
            state = .ending(sessionID: sessionID)
            return .retryEnd

        case .warning(let severity, let warning):
            applyWarning(severity: severity, warning: warning, state: &state)

        case .engineState(let engineState):
            applyEngineState(engineState, state: &state)
        }
        return nil
    }

    private static func beginEndingIfPossible(
        state: inout PuckControllerState
    ) -> PuckControllerEffect? {
        let sessionID: String
        switch state {
        case .listening(let id), .warning(let id, _, _):
            sessionID = id
        default:
            return nil
        }
        state = .ending(sessionID: sessionID)
        return .end
    }

    private static func applyWarning(
        severity: PuckRiskLevel,
        warning: PuckWarning,
        state: inout PuckControllerState
    ) {
        guard severity != .low else { return }
        switch state {
        case .listening(let sessionID):
            state = .warning(sessionID: sessionID, severity: severity, warning: warning)
        case .warning(let sessionID, let current, _):
            guard rank(severity) > rank(current) else { return }
            state = .warning(sessionID: sessionID, severity: severity, warning: warning)
        default:
            return
        }
    }

    private static func applyEngineState(
        _ engineState: PuckProtectionState,
        state: inout PuckControllerState
    ) {
        switch engineState {
        case .idle:
            if state != .disconnected { state = .ready }
        case .starting:
            if state != .disconnected { state = .starting }
        case .listening(let sessionID):
            if case .warning = state { return }
            state = .listening(sessionID: sessionID)
        case .ending(let sessionID):
            state = .ending(sessionID: sessionID)
        case .retryEnding(let sessionID, let message):
            state = .error(message: message, retryEndSessionID: sessionID)
        case .completed:
            state = .ready
        case .error(let message):
            state = .error(message: message, retryEndSessionID: nil)
        }
    }

    private static func rank(_ level: PuckRiskLevel) -> Int {
        switch level {
        case .low: 0
        case .needsReview: 1
        case .highRisk: 2
        }
    }
}
