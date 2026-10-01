@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
import Foundation

enum MicrophoneCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case outputFormatUnavailable
    case conversionFailed(String)

    var description: String {
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

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<[Int16], Error>.Continuation?
    private var isRunning = false

    func start() async throws -> AsyncThrowingStream<[Int16], Error> {
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

        let stream = AsyncThrowingStream<[Int16], Error> { continuation in
            self.continuation = continuation
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                let samples = try Self.convert(
                    buffer,
                    with: converter,
                    outputFormat: outputFormat
                )
                if !samples.isEmpty {
                    continuation?.yield(samples)
                }
            } catch {
                continuation?.finish(throwing: error)
            }
        }
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return stream
        } catch {
            input.removeTap(onBus: 0)
            self.continuation?.finish(throwing: error)
            self.continuation = nil
            throw error
        }
    }

    func stop() {
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
