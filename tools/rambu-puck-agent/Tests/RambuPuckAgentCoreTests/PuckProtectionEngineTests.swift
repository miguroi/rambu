import Foundation
import XCTest
@testable import RambuPuckAgentCore

private enum TestFailure: Error {
    case capture
    case stream
}

private final class FakeAudioCapture: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<[Int16], Error>.Continuation?
    private var starts = 0
    private var stops = 0
    var startError: Error?

    func start() async throws -> AsyncThrowingStream<[Int16], Error> {
        try lock.withLock {
            if let startError { throw startError }
            starts += 1
            return AsyncThrowingStream { continuation in
                self.continuation = continuation
            }
        }
    }

    func stop() {
        lock.lock()
        stops += 1
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }

    func yield(_ samples: [Int16]) {
        lock.withLock { continuation }?.yield(samples)
    }

    func fail(_ error: Error) {
        let continuation = lock.withLock { continuation }
        continuation?.finish(throwing: error)
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
}

private actor EngineTransport {
    private var results: [Result<(Data, HTTPURLResponse), Error>]
    private(set) var requests: [URLRequest] = []
    private let capture: FakeAudioCapture?
    private(set) var stopCountAtFinalUpload: Int?

    init(
        _ results: [Result<(Data, HTTPURLResponse), Error>],
        capture: FakeAudioCapture? = nil
    ) {
        self.results = results
        self.capture = capture
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if request.value(forHTTPHeaderField: "X-Rambu-Final") == "true" {
            stopCountAtFinalUpload = capture?.stopCount
        }
        return try results.removeFirst().get()
    }
}

final class PuckProtectionEngineTests: XCTestCase {
    func testStartCreatesSessionBeforeOpeningCaptureThenEndUploadsOneFinalChunk() async throws {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((sessionJSON(id: "session-1", nextSequence: 0), response(201))),
            .success((sessionJSON(id: "session-1", nextSequence: 1), response(200))),
            .success((sessionJSON(id: "session-1", status: "completed", nextSequence: 2), response(200))),
        ], capture: capture)
        let engine = makeEngine(transport: transport, capture: capture, framesPerChunk: 2)

        try await engine.start(callID: UUID(), startedAt: .now)
        XCTAssertEqual(capture.startCount, 1)
        capture.yield([1, 2])
        try await waitUntil { await transport.requests.count == 3 }
        try await engine.end()

        let requests = await transport.requests
        let uploads = requests.filter { $0.url?.path.contains("/chunks") == true }
        XCTAssertEqual(uploads.map { $0.value(forHTTPHeaderField: "X-Rambu-Sequence") }, ["0", "1"])
        XCTAssertEqual(uploads.map { $0.value(forHTTPHeaderField: "X-Rambu-Final") }, ["false", "true"])
        let stoppedBeforeFinal = await transport.stopCountAtFinalUpload
        XCTAssertEqual(stoppedBeforeFinal, 1)
        let state = await engine.currentState()
        XCTAssertEqual(state, .completed(sessionID: "session-1"))
    }

    func testSessionCreationFailureNeverStartsCapture() async {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((Data(#"{"detail":"unavailable"}"#.utf8), response(503))),
        ])
        let engine = makeEngine(transport: transport, capture: capture)

        do {
            try await engine.start(callID: UUID(), startedAt: .now)
            XCTFail("Expected start failure")
        } catch {}

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(capture.stopCount, 0)
        let state = await engine.currentState()
        guard case .error = state else { return XCTFail("Expected error state") }
    }

    func testChunkUploadRetriesInOrderThroughTheExistingAPI() async throws {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((sessionJSON(id: "session-1", nextSequence: 0), response(201))),
            .failure(URLError(.networkConnectionLost)),
            .success((sessionJSON(id: "session-1", nextSequence: 1), response(200))),
            .success((sessionJSON(id: "session-1", status: "completed", nextSequence: 2), response(200))),
        ])
        let engine = makeEngine(
            transport: transport,
            capture: capture,
            framesPerChunk: 2,
            retryDelays: [0]
        )

        try await engine.start(callID: UUID(), startedAt: .now)
        capture.yield([1, 2])
        try await waitUntil { await transport.requests.count == 4 }
        try await engine.end()

        let uploads = await transport.requests.filter { $0.url?.path.contains("/chunks") == true }
        XCTAssertEqual(uploads.map { $0.value(forHTTPHeaderField: "X-Rambu-Sequence") }, ["0", "0", "1"])
    }

    func testFailedEndRetainsFinalChunkAndRetryDoesNotReopenCapture() async throws {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((sessionJSON(id: "session-1", nextSequence: 0), response(201))),
            .success((Data(#"{"detail":"temporary"}"#.utf8), response(503))),
            .success((sessionJSON(id: "session-1", status: "completed", nextSequence: 1), response(200))),
        ])
        let engine = makeEngine(transport: transport, capture: capture)

        try await engine.start(callID: UUID(), startedAt: .now)
        do {
            try await engine.end()
            XCTFail("Expected end failure")
        } catch {}

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        let failedState = await engine.currentState()
        guard case .retryEnding = failedState else { return XCTFail("Expected retry-ending state") }

        try await engine.retryEnd()

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        let finalRequests = await transport.requests.filter {
            $0.value(forHTTPHeaderField: "X-Rambu-Final") == "true"
        }
        XCTAssertEqual(finalRequests.count, 2)
    }

    func testAuthenticationFailureStopsCaptureAndDoesNotRestart() async throws {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((sessionJSON(id: "session-1", nextSequence: 0), response(201))),
            .success((Data(#"{"detail":"Token puck tidak valid."}"#.utf8), response(401))),
        ])
        let engine = makeEngine(transport: transport, capture: capture, framesPerChunk: 2)

        try await engine.start(callID: UUID(), startedAt: .now)
        capture.yield([1, 2])
        try await waitUntil {
            let state = await engine.currentState()
            if case .error = state { return true }
            return false
        }

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        let state = await engine.currentState()
        guard case .error = state else { return XCTFail("Expected error state") }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(capture.startCount, 1)
    }

    func testStreamFailureStopsCaptureAndNeverAutomaticallyRestarts() async throws {
        let capture = FakeAudioCapture()
        let transport = EngineTransport([
            .success((Data(#"{"detail":"missing"}"#.utf8), response(404))),
            .success((sessionJSON(id: "session-1", nextSequence: 0), response(201))),
        ])
        let engine = makeEngine(transport: transport, capture: capture)

        try await engine.start(callID: UUID(), startedAt: .now)
        capture.fail(TestFailure.stream)
        try await waitUntil { capture.stopCount == 1 }

        XCTAssertEqual(capture.startCount, 1)
        let state = await engine.currentState()
        guard case .error = state else { return XCTFail("Expected error state") }
    }

    private func makeEngine(
        transport: EngineTransport,
        capture: FakeAudioCapture,
        framesPerChunk: Int = 80_000,
        retryDelays: [UInt64] = []
    ) -> PuckProtectionEngine {
        let api = PuckAPI(
            serverURL: URL(string: "https://api.rambu.sfatimah.com")!,
            token: "puck-token",
            retryDelaysNanoseconds: retryDelays,
            transport: { request in try await transport.send(request) }
        )
        return PuckProtectionEngine(api: api, capture: capture, framesPerChunk: framesPerChunk)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.rambu.sfatimah.com")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func sessionJSON(
    id: String,
    status: String = "listening",
    nextSequence: Int
) -> Data {
    Data(
        """
        {"id":"\(id)","status":"\(status)","end_requested":false,"next_sequence":\(nextSequence),"masked_transcript":"Halo","assessment":null}
        """.utf8
    )
}
