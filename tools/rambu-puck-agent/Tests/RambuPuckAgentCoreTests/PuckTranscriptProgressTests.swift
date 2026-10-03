import XCTest
@testable import RambuPuckAgentCore

final class PuckTranscriptProgressTests: XCTestCase {
    func testPrintsOnlyTheNewMaskedTextFromEachCumulativeTranscript() {
        var progress = PuckTranscriptProgress()

        XCTAssertEqual(
            progress.line(sequence: 0, cumulativeTranscript: "Halo, saya dari pihak bank."),
            "🎙 Heard [chunk 1]: Halo, saya dari pihak bank."
        )
        XCTAssertEqual(
            progress.line(
                sequence: 1,
                cumulativeTranscript: "Halo, saya dari pihak bank. Tolong berikan [KODE]."
            ),
            "🎙 Heard [chunk 2]: Tolong berikan [KODE]."
        )
    }

    func testPrintsNoSpeechWhenAChunkAddsNoTranscript() {
        var progress = PuckTranscriptProgress()

        XCTAssertEqual(
            progress.line(sequence: 0, cumulativeTranscript: ""),
            "🎙 Heard [chunk 1]: (no speech detected)"
        )
        _ = progress.line(sequence: 1, cumulativeTranscript: "Halo.")
        XCTAssertEqual(
            progress.line(sequence: 2, cumulativeTranscript: "Halo."),
            "🎙 Heard [chunk 3]: (no speech detected)"
        )
    }
}
