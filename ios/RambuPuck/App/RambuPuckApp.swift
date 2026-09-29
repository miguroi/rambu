import SwiftUI

@main
struct RambuPuckApp: App {
    @State private var model = DemoLaunch.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
                .tint(Brand.teal)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            content
                .id(model.onboardingComplete ? model.persona.rawValue : "onboarding")
            ToastOverlay()
        }
        .animation(.smooth(duration: 0.35), value: model.persona)
        .animation(.smooth(duration: 0.35), value: model.onboardingComplete)
        .sheet(isPresented: $model.showDemoSheet) {
            DemoSheet()
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.onboardingComplete {
            OnboardingFlow()
        } else if model.persona.isParent {
            ParentRoot()
        } else {
            GuardianRoot()
        }
    }
}

/// Variabel lingkungan untuk demo dan screenshot. Kirim lewat simctl dengan awalan SIMCTL_CHILD_.
///
///     RAMBU_PERSONA=ratna|sinta|richard     peran awal
///     RAMBU_SKIP_ONBOARDING=1               langsung ke beranda
///     RAMBU_FAST=1                          potongan audio tiap 0,7 detik, bukan 5 detik
///     RAMBU_SCENE=<adegan>[:<skenario>]     buka adegan tertentu (lihat apply)
@MainActor
enum DemoLaunch {
    static func makeModel() -> AppModel {
        let env = ProcessInfo.processInfo.environment
        let isTesting = env["XCTestConfigurationFilePath"] != nil
        let fast = env["RAMBU_FAST"] == "1"
        let scene = env["RAMBU_SCENE"]

        let model = AppModel(
            persona: Persona(rawValue: env["RAMBU_PERSONA"] ?? "") ?? .ratna,
            onboardingComplete: env["RAMBU_SKIP_ONBOARDING"] == "1" || (scene != nil && !(scene!.hasPrefix("onboarding"))),
            analysis: ScenarioAnalysis(
                interval: fast ? .milliseconds(700) : .seconds(5),
                initialDelay: fast ? .milliseconds(300) : .milliseconds(1200)
            ),
            liveActivities: !isTesting,
            notifications: !isTesting
        )
        if let scene, !isTesting { apply(scene, to: model) }
        return model
    }

    private static func apply(_ scene: String, to model: AppModel) {
        let parts = scene.split(separator: ":").map(String.init)
        let key = parts.first ?? ""
        let scenario = Scenario.all.first { $0.id == parts.dropFirst().first } ?? .bankOTP

        switch key {
        case "onboarding":
            model.onboardingStep = OnboardingStep(rawValue: parts.dropFirst().first ?? "") ?? .welcome
        case "history":
            model.parentTab = .history
        case "puck":
            model.parentTab = .puck
        case "guardian-home":
            model.switchPersona(.sinta)
        case "call":
            model.startCall(scenario)
        case "call-decided":
            let task = model.startCall(scenario)
            Task {
                await task.value
                if let id = model.alerts.first?.id { model.simulateDecision(by: .sinta, .scam, on: id) }
            }
        case "alert", "alert-locked", "alert-mine", "guardian-alert-home":
            let task = model.startCall(scenario)
            Task {
                await task.value
                model.switchPersona(.sinta)
                guard let id = model.alerts.first?.id else { return }
                if key == "alert-locked" { model.simulateDecision(by: .richard, .scam, on: id) }
                if key == "alert-mine" { model.decide(.scam, on: id) }
                if key != "guardian-alert-home" { model.openAlert(id) }
                model.toast = nil
            }
        default:
            break
        }
    }
}
