import XCTest
@testable import RambuPuckController

final class CredentialStoreTests: XCTestCase {
    func testSaveLoadAndClearUseAnIsolatedKeychainItem() throws {
        let suffix = UUID().uuidString
        let store = PuckCredentialStore(
            service: "id.rambu.puck.tests.\(suffix)",
            account: "controller"
        )
        defer { try? store.clear() }
        let credential = PuckCredential(
            puckID: "puck-1",
            familyID: "family-1",
            displayName: "Mac puck",
            accessToken: "secret-test-token"
        )

        XCTAssertNil(try store.load())
        try store.save(credential)
        XCTAssertEqual(try store.load(), credential)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
