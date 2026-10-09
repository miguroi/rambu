import XCTest
@testable import RambuPuckController

private final class FakeHotKeyRegistrar: HotKeyRegistering, @unchecked Sendable {
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private var handler: (@Sendable () -> Void)?

    func register(handler: @escaping @Sendable () -> Void) throws {
        registerCount += 1
        self.handler = handler
    }

    func unregister() {
        unregisterCount += 1
        handler = nil
    }

    func fire() { handler?() }
}

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    func testRegistrationDeliversActionAndReplacementUnregistersOldBinding() async throws {
        let registrar = FakeHotKeyRegistrar()
        let hotKey = GlobalHotKey(registrar: registrar)
        var actions = 0

        try hotKey.register { actions += 1 }
        registrar.fire()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(actions, 1)

        try hotKey.register { actions += 10 }
        XCTAssertEqual(registrar.registerCount, 2)
        XCTAssertEqual(registrar.unregisterCount, 1)
        registrar.fire()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(actions, 11)

        hotKey.unregister()
        XCTAssertEqual(registrar.unregisterCount, 2)
    }
}
