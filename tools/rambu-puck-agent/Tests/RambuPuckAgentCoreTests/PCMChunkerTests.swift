import XCTest
@testable import RambuPuckAgentCore

final class PCMChunkerTests: XCTestCase {
    func testExactlyFiveSecondsProducesOneOrderedChunk() {
        var chunker = PCMChunker()

        let chunks = chunker.append(Array(repeating: 7, count: 80_000))

        XCTAssertEqual(chunks.map(\.sequence), [0])
        XCTAssertEqual(chunks[0].samples.count, 80_000)
        XCTAssertFalse(chunks[0].isFinal)
    }

    func testAppendPreservesRemainderAndFinishFlushesItOnce() {
        var chunker = PCMChunker()

        let chunks = chunker.append(Array(repeating: 3, count: 80_010))
        let final = chunker.finish()
        let secondFinish = chunker.finish()

        XCTAssertEqual(chunks.map(\.sequence), [0])
        XCTAssertEqual(final?.sequence, 1)
        XCTAssertEqual(final?.samples.count, 10)
        XCTAssertEqual(final?.isFinal, true)
        XCTAssertNil(secondFinish)
    }

    func testFinishAfterExactBoundaryEmitsOneZeroFrameFinalChunk() {
        var chunker = PCMChunker()
        _ = chunker.append(Array(repeating: 1, count: 80_000))

        let final = chunker.finish()

        XCTAssertEqual(final?.sequence, 1)
        XCTAssertEqual(final?.samples, [])
        XCTAssertEqual(final?.isFinal, true)
    }
}
