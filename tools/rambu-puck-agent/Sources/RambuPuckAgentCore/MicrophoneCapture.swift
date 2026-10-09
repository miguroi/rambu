@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
import Foundation

public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<[Int16], Error>
    func stop()
}

public enum MicrophoneCaptureError: Error, CustomStringConvertible, Sendable {
    case permissionDenied
    case outputFormatUnavailable
    case conversionFailed(String)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied in macOS System Settings."
        case .outputFormatUnavailable:
            return "The microphone cannot be converted to 16 kHz mono PCM."
        case .conversionFailed(let detail):
            return "Microphone format conversion failed: \(detail)"
        }
    }
}

public final class MicrophoneCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<[Int16], Error>.Continuation?
    private var isRunning = false

    public init() {}

    public func start() async throws -> AsyncThrowingStream<[Int16], Error> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw MicrophoneCaptureError.permissionDenied
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MicrophoneCaptureError.outputFormatUnavailable
        }

        let pair = AsyncThrowingStream<[Int16], Error>.makeStream()
        let stream = pair.stream
        let streamContinuation = pair.continuation
        self.continuation = streamContinuation
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
            do {
                let samples = try Self.convert(
                    buffer,
                    with: converter,
                    outputFormat: outputFormat
                )
                if !samples.isEmpty {
                    streamContinuation.yield(samples)
                }
            } catch {
                streamContinuation.finish(throwing: error)
            }
        }
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return stream
        } catch {
            input.removeTap(onBus: 0)
            streamContinuation.finish(throwing: error)
            self.continuation = nil
            throw error
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) throws -> [Int16] {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw MicrophoneCaptureError.outputFormatUnavailable
        }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, state in
            if suppliedInput {
                state.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            state.pointee = .haveData
            return input
        }
        if status == .error || conversionError != nil {
            throw MicrophoneCaptureError.conversionFailed(
                conversionError?.localizedDescription ?? "unknown converter error"
            )
        }
        guard let channel = output.int16ChannelData?[0] else {
            throw MicrophoneCaptureError.outputFormatUnavailable
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
