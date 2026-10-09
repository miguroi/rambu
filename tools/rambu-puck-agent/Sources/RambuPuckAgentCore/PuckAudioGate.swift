import Foundation

public enum PuckAudioGateEvent: Equatable, Sendable {
    case activated(preRoll: [Int16])
    case ended
}

public struct PuckAudioGate: Sendable {
    private enum State: Sendable {
        case waiting
        case active
        case ended
    }

    private let thresholdAmplitude: Double
    private let activationFrames: Int
    private let maximumPreRollFrames: Int
    private let silenceFramesToEnd: Int

    private var state: State
    private var activityFrames = 0
    private var silentFrames = 0
    private var preRoll: [Int16] = []

    public init(
        sampleRate: Int = 16_000,
        thresholdDBFS: Double = -38,
        activationSeconds: Double = 0.75,
        preRollSeconds: Double = 2,
        silenceSecondsToEnd: Double = 12,
        initiallyActive: Bool = false
    ) {
        precondition(sampleRate > 0)
        precondition(activationSeconds > 0)
        precondition(preRollSeconds >= 0)
        precondition(silenceSecondsToEnd > 0)
        thresholdAmplitude = Double(Int16.max) * pow(10, thresholdDBFS / 20)
        activationFrames = max(1, Int(Double(sampleRate) * activationSeconds))
        maximumPreRollFrames = max(0, Int(Double(sampleRate) * preRollSeconds))
        silenceFramesToEnd = max(1, Int(Double(sampleRate) * silenceSecondsToEnd))
        state = initiallyActive ? .active : .waiting
    }

    public mutating func ingest(_ samples: [Int16]) -> PuckAudioGateEvent? {
        guard !samples.isEmpty else { return nil }
        let activeAudio = rootMeanSquare(samples) >= thresholdAmplitude

        switch state {
        case .waiting:
            appendToPreRoll(samples)
            if activeAudio {
                activityFrames = min(activationFrames, activityFrames + samples.count)
            } else {
                activityFrames = max(0, activityFrames - samples.count)
            }
            guard activityFrames >= activationFrames else { return nil }
            state = .active
            silentFrames = 0
            return .activated(preRoll: preRoll)

        case .active:
            if activeAudio {
                silentFrames = 0
            } else {
                silentFrames += samples.count
            }
            guard silentFrames >= silenceFramesToEnd else { return nil }
            state = .ended
            return .ended

        case .ended:
            return nil
        }
    }

    private mutating func appendToPreRoll(_ samples: [Int16]) {
        guard maximumPreRollFrames > 0 else { return }
        preRoll.append(contentsOf: samples)
        if preRoll.count > maximumPreRollFrames {
            preRoll.removeFirst(preRoll.count - maximumPreRollFrames)
        }
    }

    private func rootMeanSquare(_ samples: [Int16]) -> Double {
        let sum = samples.reduce(into: 0.0) { partial, sample in
            let value = Double(sample)
            partial += value * value
        }
        return sqrt(sum / Double(samples.count))
    }
}
