import Foundation
import Observation

/// Satu sumber kebenaran yang diamati seluruh fitur Rambu.
/// Objek ini hanya menyimpan state dan nilai turunan; efek samping tetap milik ViewModel.
@MainActor
@Observable
final class AppState {
    var persona: Persona
    var onboardingComplete: Bool
    var onboardingStep: OnboardingStep = .welcome
    var puck: PuckState

    var parent: Person = .ratna
    var guardians: [Person] = Person.guardians
    var extraParents: [Person] = []

    var session: CallSession?
    var isCallScreenPresented = false
    var alerts: [FamilyAlert] = []
    var history: [CallRecord]
    var unanswered: Set<UUID> = []

    var parentTab: ParentTab = .home
    var guardianTab: GuardianTab = .home
    var guardianPath: [UUID] = []
    var showDemoSheet = false
    var showProfile = false
    var showCallStatus = false
    var toast: Toast?

    var narrationEnabled = true
    var notificationsAuthorized = false
    var isOnline = true
    var pendingInviteCode: String?
    var pilotConnected = false
    var pilotInviteCode: String?
    var pilotRole: String?
    var pilotError: String?
    var pilotServerURL = UserDefaults.standard.string(forKey: "pilotServerURL") ?? "http://127.0.0.1:8000"

    var simulateOffline = false
    var bluetoothOn = true
    var speakerOffNextCall = false
    var hidesNotificationIssue = false

    init(
        persona: Persona = .ratna,
        onboardingComplete: Bool = false,
        now: Date = .now
    ) {
        self.persona = persona
        self.onboardingComplete = onboardingComplete
        puck = onboardingComplete ? .demo : .unpaired
        history = CallRecord.seed(now: now)
    }

    var currentPerson: Person { person(for: persona) }

    func person(for persona: Persona) -> Person {
        switch persona {
        case .ratna: parent
        case .sinta: guardians.first ?? .sinta
        case .richard: guardians.dropFirst().first ?? .richard
        }
    }

    var protectedParents: [Person] { [parent] + extraParents }

    var activeAlert: FamilyAlert? {
        guard let id = session?.id else { return nil }
        return alerts.first { $0.id == id }
    }

    var featuredAlert: FamilyAlert? {
        alerts.first { $0.decision == nil } ?? alerts.first { !$0.callEnded }
    }

    func otherGuardians(than person: Person) -> [Person] {
        guardians.filter { $0 != person }
    }

    var issues: [SystemIssue] {
        guard onboardingComplete else { return [] }
        var values: [SystemIssue] = []
        if !notificationsAuthorized && !hidesNotificationIssue { values.append(.notificationsOff) }
        if !isOnline || simulateOffline { values.append(.offline) }
        if persona.isParent {
            if !bluetoothOn {
                values.append(.bluetoothOff)
            } else if !puck.isConnected {
                values.append(.puckDisconnected)
            } else if puck.battery <= 20 {
                values.append(.puckLowBattery)
            }
        }
        return values
    }

    var savedState: SavedState {
        SavedState(
            onboardingComplete: onboardingComplete,
            persona: persona,
            parent: parent,
            guardians: guardians,
            extraParents: extraParents,
            history: history,
            puck: puck,
            narrationEnabled: narrationEnabled
        )
    }

    func restore(_ saved: SavedState) {
        onboardingComplete = saved.onboardingComplete
        persona = saved.persona
        parent = saved.parent
        guardians = saved.guardians
        extraParents = saved.extraParents
        history = saved.history
        puck = saved.puck
        narrationEnabled = saved.narrationEnabled
    }
}
