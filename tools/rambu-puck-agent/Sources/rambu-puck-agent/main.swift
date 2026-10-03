import Darwin
import Foundation
import RambuPuckAgentCore

private actor StopSignal {
    private(set) var requested = false
    private(set) var failure: String?

    func request() {
        requested = true
    }

    func fail(_ message: String) {
        failure = message
        requested = true
    }
}

private enum AgentRuntimeError: Error, CustomStringConvertible {
    case monitoring(String)

    var description: String {
        switch self {
        case .monitoring(let message):
            return "Session monitoring failed: \(message)"
        }
    }
}

@main
struct RambuPuckAgentMain {
    static func main() async {
        do {
            let arguments = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
            switch arguments {
            case .help:
                printUsage()
            case .pair(let code, let name):
                try await pair(code: code, name: name)
            case .listen:
                try await listen()
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func pair(code: String, name: String) async throws {
        let configuration = try AgentConfiguration(
            environment: ProcessInfo.processInfo.environment,
            command: .pair
        )
        let api = PuckAPI(serverURL: configuration.serverURL, token: nil)
        let puck = try await api.pair(code: code, displayName: name)
        print(puck.accessToken)
    }

    private static func listen() async throws {
        let configuration = try AgentConfiguration(
            environment: ProcessInfo.processInfo.environment,
            command: .listen
        )
        let api = PuckAPI(serverURL: configuration.serverURL, token: configuration.puckToken)
        print("Rambu puck agent is waiting for an active call.")
        while !Task.isCancelled {
            if let session = try await api.activeSession() {
                try await record(session: session, api: api)
                print("Protection session \(session.id) completed.")
            } else {
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func record(session: ProtectionSession, api: PuckAPI) async throws {
        print("Active call found. Capturing external audio with the Mac microphone.")
        let capture = MicrophoneCapture()
        let stream = try await capture.start()
        let signal = StopSignal()
        let monitor = Task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(500))
                    guard let current = try await api.activeSession() else {
                        await signal.request()
                        return
                    }
                    if current.id != session.id || current.endRequested {
                        await signal.request()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await signal.fail(String(describing: error))
            }
        }
        defer {
            monitor.cancel()
            capture.stop()
        }

        var chunker = PCMChunker()
        var transcriptProgress = PuckTranscriptProgress()
        var warningGate = PuckWarningGate()
        for try await samples in stream {
            for chunk in chunker.append(samples) {
                let updated = try await api.uploadChunk(
                    sessionID: session.id,
                    sequence: chunk.sequence,
                    final: false,
                    wav: WAVEncoder.encode(samples: chunk.samples)
                )
                emitTranscript(
                    transcriptProgress.line(
                        sequence: chunk.sequence,
                        cumulativeTranscript: updated.maskedTranscript
                    )
                )
                if let warning = warningGate.warning(for: updated.assessment) {
                    emit(warning)
                }
            }
            if await signal.requested { break }
        }
        if let failure = await signal.failure {
            throw AgentRuntimeError.monitoring(failure)
        }
        capture.stop()
        if let final = chunker.finish() {
            let updated = try await api.uploadChunk(
                sessionID: session.id,
                sequence: final.sequence,
                final: true,
                wav: WAVEncoder.encode(samples: final.samples)
            )
            emitTranscript(
                transcriptProgress.line(
                    sequence: final.sequence,
                    cumulativeTranscript: updated.maskedTranscript
                )
            )
            if let warning = warningGate.warning(for: updated.assessment) {
                emit(warning)
            }
        }
    }

    private static func emitTranscript(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }

    private static func emit(_ warning: PuckWarning) {
        let message = """
        \u{7}
        ⚠️ RAMBU WARNING: \(warning.title)
        \(warning.recommendedAction)

        """
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func printUsage() {
        print(
            """
            Usage:
              rambu-puck-agent pair --code 123456 --name "Mac puck"
              rambu-puck-agent listen

            Required environment:
              RAMBU_SERVER_URL   Backend base URL
              RAMBU_PUCK_TOKEN   Token printed by pair (listen only)
            """
        )
    }
}
