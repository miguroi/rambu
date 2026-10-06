import Foundation
import XCTest
@testable import RambuPuckAgentCore
@testable import RambuPuckController

private final class MemoryCredentialStore: PuckCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: PuckCredential?

    init(_ value: PuckCredential? = nil) { self.value = value }
    func load() throws -> PuckCredential? { lock.withLock { value } }
    func save(_ credential: PuckCredential) throws { lock.withLock { value = credential } }
    func clear() throws { lock.withLock { value = nil } }
    func removeBehindController() { lock.withLock { value = nil } }
}

private actor FakePairer: PuckPairing {
    private(set) var calls: [(String, String)] = []
    let result: PairedPuck

    init(result: PairedPuck) { self.result = result }
    func pair(code: String, displayName: String) async throws -> PairedPuck {
        calls.append((code, displayName))
        return result
    }
}

private actor FakeProtection: PuckProtectionServing {
    nonisolated let events: AsyncStream<PuckProtectionEvent>
    private let continuation: AsyncStream<PuckProtectionEvent>.Continuation
    private(set) var starts = 0
    private(set) var ends = 0
    private(set) var retries = 0

    init() {
        let pair = AsyncStream<PuckProtectionEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start(callID: UUID, startedAt: Date) async throws { starts += 1 }
    func end() async throws { ends += 1 }
    func retryEnd() async throws { retries += 1 }
    func emit(_ event: PuckProtectionEvent) { continuation.yield(event) }
    func counts() -> (starts: Int, ends: Int, retries: Int) { (starts, ends, retries) }
}

@MainActor
final class PuckControllerViewModelTests: XCTestCase {
    private let credential = PuckCredential(
        puckID: "puck-1",
        familyID: "family-1",
        displayName: "Mac puck",
        accessToken: "token-1"
    )

    func testMissingKeychainItemOverridesRememberedPreferences() {
        let defaults = isolatedDefaults()
        defaults.set("https://old.example.com", forKey: PuckControllerViewModel.serverURLKey)
        defaults.set("Old puck", forKey: PuckControllerViewModel.displayNameKey)

        let model = makeModel(store: MemoryCredentialStore(), defaults: defaults)

        XCTAssertEqual(model.state, .disconnected)
        XCTAssertEqual(model.serverURLText, "https://old.example.com")
    }

    func testInvalidPairingInputNeverCreatesAnAPIClient() async {
        let calls = LockedCounter()
        let model = makeModel(
            store: MemoryCredentialStore(),
            pairerFactory: { _ in calls.increment(); return FakePairer(result: pairedPuck()) }
        )
        model.serverURLText = "not a URL"
        model.pairingCode = "12 3456"

        await model.pair()

        XCTAssertEqual(calls.value, 0)
        guard case .error = model.state else { return XCTFail("Expected local validation error") }
    }

    func testSuccessfulPairTrimsInputAndStoresCredential() async throws {
        let store = MemoryCredentialStore()
        let pairer = FakePairer(result: pairedPuck())
        let model = makeModel(store: store, pairerFactory: { _ in pairer })
        model.pairingCode = " 123456 "
        model.displayName = " Mac puck "

        await model.pair()

        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(try store.load()?.accessToken, "token-1")
        let calls = await pairer.calls
        XCTAssertEqual(calls.first?.0, "123456")
        XCTAssertEqual(calls.first?.1, "Mac puck")
    }

    func testStartChecksCredentialStillExistsAndDoesNotCallEngineWhenDeleted() async {
        let store = MemoryCredentialStore(credential)
        let engine = FakeProtection()
        let model = makeModel(store: store, engine: engine)
        store.removeBehindController()

        await model.start()

        XCTAssertEqual(model.state, .disconnected)
        let counts = await engine.counts()
        XCTAssertEqual(counts.starts, 0)
    }

    func testStartEndAndEngineEventsProjectIntoPublishedState() async throws {
        let engine = FakeProtection()
        let model = makeModel(store: MemoryCredentialStore(credential), engine: engine)

        await model.start()
        var counts = await engine.counts()
        XCTAssertEqual(counts.starts, 1)
        await engine.emit(.state(.listening(sessionID: "session-1")))
        await engine.emit(.transcript("masked line"))
        let warning = PuckWarning(title: "Penipuan", recommendedAction: "Tutup")
        await engine.emit(.warning(severity: .highRisk, warning: warning))
        try await waitUntil {
            model.transcriptLines == ["masked line"] && model.latestWarning == warning
        }
        XCTAssertEqual(model.latestWarning, warning)

        await model.end()
        counts = await engine.counts()
        XCTAssertEqual(counts.ends, 1)
    }

    private func makeModel(
        store: MemoryCredentialStore,
        defaults: UserDefaults? = nil,
        engine: FakeProtection = FakeProtection(),
        pairerFactory: @escaping PuckPairerFactory = { _ in FakePairer(result: pairedPuck()) }
    ) -> PuckControllerViewModel {
        PuckControllerViewModel(
            credentialStore: store,
            defaults: defaults ?? isolatedDefaults(),
            pairerFactory: pairerFactory,
            engineFactory: { _, _ in engine }
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "id.rambu.puck.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out")
    }

}

private func pairedPuck() -> PairedPuck {
    PairedPuck(
        puckID: "puck-1",
        familyID: "family-1",
        displayName: "Mac puck",
        accessToken: "token-1"
    )
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
