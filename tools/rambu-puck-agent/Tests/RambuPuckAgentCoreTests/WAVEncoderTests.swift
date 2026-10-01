import XCTest
@testable import RambuPuckAgentCore

final class WAVEncoderTests: XCTestCase {
    func testEncodesCanonical16KHzMonoInt16HeaderAndSamples() throws {
        let data = WAVEncoder.encode(samples: [1, -2, 32767])

        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(littleEndianUInt32(data, at: 4), 42)
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(littleEndianUInt16(data, at: 22), 1)
        XCTAssertEqual(littleEndianUInt32(data, at: 24), 16_000)
        XCTAssertEqual(littleEndianUInt16(data, at: 34), 16)
        XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(littleEndianUInt32(data, at: 40), 6)
        XCTAssertEqual(Array(data[44...]), [1, 0, 254, 255, 255, 127])
    }

    func testEncodesValidZeroFrameFinalWave() throws {
        let data = WAVEncoder.encode(samples: [])

        XCTAssertEqual(data.count, 44)
        XCTAssertEqual(littleEndianUInt32(data, at: 40), 0)
    }

    private func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
