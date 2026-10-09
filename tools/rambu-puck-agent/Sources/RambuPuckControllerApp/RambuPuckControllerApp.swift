import AppKit
import Combine
import RambuPuckAgentCore
import RambuPuckController
import SwiftUI

@MainActor
private final class ControllerRuntime: ObservableObject {
    let model: PuckControllerViewModel
    private let hotKey: GlobalHotKey

    init() {
        let model = PuckControllerViewModel()
        self.model = model
        self.hotKey = GlobalHotKey()
        try? hotKey.register { [weak model] in
            guard let model else { return }
            Task { await model.toggleFromShortcut() }
        }
    }

    func quit() {
        Task {
            switch model.state {
            case .listening, .warning:
                await model.end()
            default:
                break
            }
            hotKey.unregister()
            NSApplication.shared.terminate(nil)
        }
    }
}

@main
struct RambuPuckControllerApp: App {
    @StateObject private var runtime = ControllerRuntime()

    var body: some Scene {
        MenuBarExtra {
            PuckMenuView(model: runtime.model, onQuit: runtime.quit)
        } label: {
            Image(systemName: "shield.lefthalf.filled")
        }
        .menuBarExtraStyle(.window)

        Window("Transkrip Rambu", id: "transcript") {
            TranscriptWindow(model: runtime.model)
        }
    }
}
