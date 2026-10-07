import Foundation
import Testing
@testable import RambuPuck

@MainActor
struct ProfileViewModelTests {
    @Test("Profil menyimpan perubahan ke state dan penyimpanan yang sama")
    func profilePersistsSharedState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rambu-profile-\(UUID()).json")
        let store = LocalStore(url: url)
        defer { store.clear() }
        let state = AppState(onboardingComplete: true, allowsDemoControls: true)
        let profile = ProfileViewModel(
            state: state,
            notifier: RambuNotifier(enabled: false),
            narrator: Narrator(enabled: false),
            network: NetworkMonitor(),
            store: store
        )

        profile.renameParent("Bu Sri")
        let added = profile.addProtectedParent(code: "715204")

        #expect(state.parent.name == "Bu Sri")
        #expect(added?.name == "Pak Hadi")
        #expect(try #require(store.load()).parent.name == "Bu Sri")
        #expect(try #require(store.load()).extraParents == [added])
    }
}
