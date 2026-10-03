import XCTest
@testable import RambuPuckAgentCore

final class CLIArgumentsTests: XCTestCase {
    func testParsesPairAndListenCommandsWithoutGuessingMissingValues() throws {
        XCTAssertEqual(
            try CLIArguments.parse(["pair", "--code", "123456", "--name", "Mac puck"]),
            .pair(code: "123456", name: "Mac puck")
        )
        XCTAssertEqual(try CLIArguments.parse(["listen"]), .listen(detectAudio: false))
        XCTAssertEqual(
            try CLIArguments.parse(["listen", "--detect-audio"]),
            .listen(detectAudio: true)
        )
        XCTAssertEqual(try CLIArguments.parse(["--help"]), .help)
        XCTAssertThrowsError(try CLIArguments.parse(["pair", "--code", "123456"]))
        XCTAssertThrowsError(try CLIArguments.parse(["listen", "--unknown"]))
        XCTAssertThrowsError(try CLIArguments.parse(["unknown"]))
    }
}
