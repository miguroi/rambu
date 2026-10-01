import Foundation
import Observation

/// Mengelola sinkronisasi pilot dua iPhone tanpa mencampurnya dengan UI profil.
@MainActor
@Observable
final class PilotViewModel {
    @ObservationIgnored let state: AppState
    @ObservationIgnored private let pilot: PilotSync?
    @ObservationIgnored private let family: FamilyViewModel
    @ObservationIgnored private let profile: ProfileViewModel

    init(state: AppState, pilot: PilotSync?, family: FamilyViewModel, profile: ProfileViewModel) {
        self.state = state
        self.pilot = pilot
        self.family = family
        self.profile = profile
    }

    func start() {
        pilot?.onProfile = { [weak self] value in self?.applyProfile(value) }
        pilot?.onAlerts = { [weak self] values in self?.applyAlerts(values) }
        pilot?.onError = { [weak state] message in state?.pilotError = message }
        state.pilotConnected = pilot?.isConnected == true
        state.pilotInviteCode = pilot?.inviteCode
        state.pilotRole = pilot?.credentials?.member.role
        pilot?.start()
    }

    func createFamily() async -> Bool {
        guard let pilot else { return false }
        state.pilotError = nil
        do {
            let code = try await pilot.createFamily(serverURL: state.pilotServerURL, parentName: state.parent.name)
            state.pilotConnected = true
            state.pilotRole = "parent"
            state.pilotInviteCode = code
            return true
        } catch {
            state.pilotError = error.localizedDescription
            return false
        }
    }

    func joinFamily(code: String) async -> Bool {
        guard let pilot else { return false }
        state.pilotError = nil
        do {
            let me = state.currentPerson
            try await pilot.joinFamily(
                serverURL: state.pilotServerURL,
                code: code,
                name: me.name,
                relation: me.relation
            )
            state.pilotConnected = true
            state.pilotRole = "guardian"
            state.pilotInviteCode = nil
            state.persona = .sinta
            profile.persist()
            return true
        } catch {
            state.pilotError = error.localizedDescription
            return false
        }
    }

    func renewInvite() async {
        guard let pilot else { return }
        state.pilotError = nil
        do {
            state.pilotInviteCode = try await pilot.renewInvite()
        } catch {
            state.pilotError = error.localizedDescription
        }
    }

    func disconnect() {
        pilot?.disconnect()
        state.pilotConnected = false
        state.pilotInviteCode = nil
        state.pilotRole = nil
        state.pilotError = nil
    }

    func refresh() async {
        await pilot?.refresh()
    }

    func publish(_ alert: FamilyAlert) {
        pilot?.publish(alert)
    }

    func submit(_ verdict: Verdict, alertID: UUID) async -> DecisionOutcome? {
        guard let outcome = await pilot?.submit(verdict, alertID: alertID) else { return nil }
        family.applyRemoteDecision(outcome, alertID: alertID)
        return outcome
    }

    func end(_ alertID: UUID) {
        pilot?.end(alertID)
    }

    func applyProfile(_ value: PilotProfileDTO) {
        state.parent = value.parent.person
        state.guardians = value.guardians.map(\.person)
        if value.member.role == "guardian" {
            state.persona = .sinta
            if let me = value.guardians.first(where: { $0.id == value.member.id })?.person {
                state.guardians = [me] + state.guardians.filter { $0.id != me.id }
            }
        } else {
            state.persona = .ratna
        }
        state.pilotConnected = true
        state.pilotRole = value.member.role
        state.pilotInviteCode = pilot?.inviteCode
        profile.persist()
    }

    func applyAlerts(_ values: [FamilyAlert]) {
        family.applyRemoteAlerts(values)
    }
}
