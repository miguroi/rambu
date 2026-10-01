public struct PCMChunk: Equatable, Sendable {
    public let sequence: Int
    public let samples: [Int16]
    public let isFinal: Bool
}

public struct PCMChunker: Sendable {
    private let framesPerChunk: Int
    private var buffered: [Int16] = []
    private var nextSequence = 0
    private var finished = false

    public init(framesPerChunk: Int = 80_000) {
        precondition(framesPerChunk > 0)
        self.framesPerChunk = framesPerChunk
    }

    public mutating func append(_ samples: [Int16]) -> [PCMChunk] {
        guard !finished else { return [] }
        buffered.append(contentsOf: samples)
        var chunks: [PCMChunk] = []
        while buffered.count >= framesPerChunk {
            let values = Array(buffered.prefix(framesPerChunk))
            buffered.removeFirst(framesPerChunk)
            chunks.append(PCMChunk(sequence: nextSequence, samples: values, isFinal: false))
            nextSequence += 1
        }
        return chunks
    }

    public mutating func finish() -> PCMChunk? {
        guard !finished else { return nil }
        finished = true
        defer { buffered.removeAll(keepingCapacity: false) }
        let chunk = PCMChunk(sequence: nextSequence, samples: buffered, isFinal: true)
        nextSequence += 1
        return chunk
    }
}
