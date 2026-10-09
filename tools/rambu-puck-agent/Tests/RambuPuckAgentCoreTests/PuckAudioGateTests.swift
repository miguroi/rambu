import XCTest
@testable import RambuPuckAgentCore

final class PuckAudioGateTests: XCTestCase {
    private let loud = Array(repeating: Int16(2_000), count: 4_000)
    private let quiet = Array(repeating: Int16(0), count: 4_000)

    func testSilenceNeverActivates() {
        var gate = PuckAudioGate()

        for _ in 0..<20 {
            XCTAssertNil(gate.ingest(quiet))
        }
    }

    func testBriefSoundSpikeDoesNotActivate() {
        var gate = PuckAudioGate()

        XCTAssertNil(gate.ingest(loud))
        XCTAssertNil(gate.ingest(quiet))
        XCTAssertNil(gate.ingest(quiet))
    }

    func testSustainedAudioActivatesWithBoundedTwoSecondPreRoll() {
        var gate = PuckAudioGate()
        for _ in 0..<12 {
            XCTAssertNil(gate.ingest(quiet))
        }

        XCTAssertNil(gate.ingest(loud))
        XCTAssertNil(gate.ingest(loud))
        let event = gate.ingest(loud)

        guard case .activated(let preRoll) = event else {
            return XCTFail("Expected sustained audio to activate the puck")
        }
        XCTAssertEqual(preRoll.count, 32_000)
        XCTAssertEqual(Array(preRoll.suffix(12_000)), Array(repeating: 2_000, count: 12_000))
    }

    func testActiveGateEndsOnlyAfterTwelveConsecutiveSilentSeconds() {
        var gate = PuckAudioGate()
        _ = gate.ingest(loud)
        _ = gate.ingest(loud)
        XCTAssertNotNil(gate.ingest(loud))

        for _ in 0..<44 {
            XCTAssertNil(gate.ingest(quiet))
        }
        XCTAssertNil(gate.ingest(loud), "Fresh audio must reset the silence timer")
        for _ in 0..<47 {
            XCTAssertNil(gate.ingest(quiet))
        }
        XCTAssertEqual(gate.ingest(quiet), .ended)
        XCTAssertNil(gate.ingest(quiet), "Ending must be emitted only once")
    }
}
