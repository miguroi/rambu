import Foundation

public enum PuckProtectionState: Equatable, Sendable {
    case idle
    case starting
    case listening(sessionID: String)
    case ending(sessionID: String)
    case retryEnding(sessionID: String, message: String)
    case completed(sessionID: String)
    case error(String)
}

public enum PuckProtectionEvent: Equatable, Sendable {
    case state(PuckProtectionState)
    case transcript(String)
    case warning(PuckWarning)
}

public enum PuckProtectionEngineError: Error, CustomStringConvertible, Sendable {
    case invalidState(PuckProtectionState)

    public var description: String {
        switch self {
        case .invalidState(let state):
            return "Protection cannot perform that action from state \(state)."
        }
    }
}

public actor PuckProtectionEngine {
    public nonisolated let events: AsyncStream<PuckProtectionEvent>

    private let api: PuckAPI
    private let capture: any AudioCapturing
    private let framesPerChunk: Int
    private let eventContinuation: AsyncStream<PuckProtectionEvent>.Continuation

    private var state: PuckProtectionState = .idle
    private var sessionID: String?
    private var baseSequence = 0
    private var chunker: PCMChunker
    private var transcriptProgress = PuckTranscriptProgress()
    private var warningGate = PuckWarningGate()
    private var streamTask: Task<Void, Never>?
    private var endRequested = false
    private var pendingFinal: PCMChunk?

    public init(
        api: PuckAPI,
        capture: any AudioCapturing = MicrophoneCapture(),
        framesPerChunk: Int = 80_000
    ) {
        precondition(framesPerChunk > 0)
        self.api = api
        self.capture = capture
        self.framesPerChunk = framesPerChunk
        self.chunker = PCMChunker(framesPerChunk: framesPerChunk)
        let pair = AsyncStream<PuckProtectionEvent>.makeStream()
        self.events = pair.stream
        self.eventContinuation = pair.continuation
    }

    deinit {
        streamTask?.cancel()
        eventContinuation.finish()
    }

    public func currentState() -> PuckProtectionState {
        state
    }

    public func start(callID: UUID, startedAt: Date) async throws {
        switch state {
        case .idle, .completed, .error:
            break
        default:
            throw PuckProtectionEngineError.invalidState(state)
        }

        resetSessionState()
        transition(to: .starting)
        let session: ProtectionSession
        do {
            session = try await api.startOrJoinSession(callID: callID, startedAt: startedAt)
        } catch {
            transition(to: .error(String(describing: error)))
            throw error
        }

        do {
            let stream = try await capture.start()
            sessionID = session.id
            baseSequence = session.nextSequence
            transition(to: .listening(sessionID: session.id))
            streamTask = Task { [weak self] in
                do {
                    for try await samples in stream {
                        guard !Task.isCancelled else { return }
                        await self?.consume(samples)
                    }
                    await self?.streamFinishedNormally()
                } catch {
                    await self?.streamFailed(error)
                }
            }
        } catch {
            capture.stop()
            transition(to: .error(String(describing: error)))
            throw error
        }
    }

    public func end() async throws {
        guard case .listening(let id) = state else {
            throw PuckProtectionEngineError.invalidState(state)
        }
        endRequested = true
        transition(to: .ending(sessionID: id))
        capture.stop()
        await streamTask?.value
        streamTask = nil

        guard let final = pendingFinal ?? chunker.finish() else {
            throw PuckProtectionEngineError.invalidState(state)
        }
        pendingFinal = final
        do {
            try await upload(final, sessionID: id)
            pendingFinal = nil
            transition(to: .completed(sessionID: id))
        } catch {
            transition(to: .retryEnding(sessionID: id, message: String(describing: error)))
            throw error
        }
    }

    public func retryEnd() async throws {
        guard case .retryEnding(let id, _) = state, let final = pendingFinal else {
            throw PuckProtectionEngineError.invalidState(state)
        }
        transition(to: .ending(sessionID: id))
        do {
            try await upload(final, sessionID: id)
            pendingFinal = nil
            transition(to: .completed(sessionID: id))
        } catch {
            transition(to: .retryEnding(sessionID: id, message: String(describing: error)))
            throw error
        }
    }

    private func resetSessionState() {
        streamTask?.cancel()
        streamTask = nil
        sessionID = nil
        baseSequence = 0
        chunker = PCMChunker(framesPerChunk: framesPerChunk)
        transcriptProgress = PuckTranscriptProgress()
        warningGate = PuckWarningGate()
        endRequested = false
        pendingFinal = nil
    }

    private func consume(_ samples: [Int16]) async {
        guard case .listening(let id) = state else { return }
        for chunk in chunker.append(samples) {
            do {
                try await upload(chunk, sessionID: id)
            } catch {
                capture.stop()
                transition(to: .error(String(describing: error)))
                streamTask?.cancel()
                return
            }
        }
    }

    private func upload(_ chunk: PCMChunk, sessionID: String) async throws {
        let sequence = baseSequence + chunk.sequence
        let updated = try await api.uploadChunk(
            sessionID: sessionID,
            sequence: sequence,
            final: chunk.isFinal,
            wav: WAVEncoder.encode(samples: chunk.samples)
        )
        eventContinuation.yield(.transcript(
            transcriptProgress.line(
                sequence: sequence,
                cumulativeTranscript: updated.maskedTranscript
            )
        ))
        if let warning = warningGate.warning(for: updated.assessment) {
            eventContinuation.yield(.warning(warning))
        }
    }

    private func streamFinishedNormally() {
        guard !endRequested, case .listening = state else { return }
        capture.stop()
        transition(to: .error("Microphone capture ended unexpectedly."))
    }

    private func streamFailed(_ error: Error) {
        guard !endRequested, case .listening = state else { return }
        capture.stop()
        transition(to: .error(String(describing: error)))
    }

    private func transition(to newState: PuckProtectionState) {
        state = newState
        eventContinuation.yield(.state(newState))
    }
}
