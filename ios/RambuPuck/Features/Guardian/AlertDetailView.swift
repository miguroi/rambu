import SwiftUI

// Detail peringatan untuk pengawas: kalimat penelepon, penerima, dan dua tombol keputusan.

// MARK: - Detail

struct AlertDetail: View {
    let alertID: UUID
    @Environment(AppState.self) private var model

    var body: some View {
        if let alert = model.alerts.first(where: { $0.id == alertID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AlertHeader(alert: alert)

                    CallEvidenceSection(evidence: alert.evidence, level: alert.level)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Penerima")
                        RecipientsCard(alert: alert)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Brand.canvas)
            .safeAreaBar(edge: .bottom) { DecisionBar(alert: alert) }
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle("Peringatan")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Peringatan tidak ditemukan", systemImage: "bell.slash")
        }
    }
}

private struct AlertHeader: View {
    let alert: FamilyAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LevelBand(level: alert.level, callEnded: alert.callEnded, startedAt: alert.startedAt)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(Brand.display(.title))
                            .foregroundStyle(Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Label(alert.callerDetail, systemImage: alert.channel.symbol)
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alert.level.soft)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }
}

private struct RecipientsCard: View {
    let alert: FamilyAlert
    @Environment(AppState.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(alert.recipients) { person in
                HStack(spacing: 12) {
                    Avatar(person: person, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person == model.currentPerson ? "\(person.name) (Anda)" : person.name)
                            .font(.headline).foregroundStyle(Brand.ink)
                        Text(status(for: person)).font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    Spacer()
                    if alert.decision?.by == person {
                        Image(systemName: alert.decision?.verdict == .scam ? "hand.raised.fill" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(alert.decision?.verdict == .scam ? Brand.danger : Brand.safe)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if person != alert.recipients.last { Divider().padding(.leading, 52) }
            }
        }
        .card(padding: 14)
    }

    private func status(for person: Person) -> String {
        if let decision = alert.decision {
            return decision.by == person
                ? "Menandai \(decision.verdict.pastTitle), \(Fmt.clock(decision.at))"
                : "Tidak perlu menjawab"
        }
        return "Menerima, \(Fmt.clock(alert.raisedAt))"
    }
}

// MARK: - Keputusan

/// Dua keputusan saja. "Aman" diberi konfirmasi karena menurunkan kewaspadaan orang tua;
/// "Penipuan" langsung terkirim karena setiap detik berarti.
private struct DecisionBar: View {
    let alert: FamilyAlert
    @Environment(AppState.self) private var model
    @Environment(AppViewModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var confirmSafe = false
    @State private var callInfo = false

    var body: some View {
        VStack(spacing: 10) {
            if let decision = alert.decision {
                decidedContent(decision)
            } else {
                HStack(spacing: 10) {
                    Button { confirmSafe = true } label: { WideLabel(title: "Aman", systemImage: "checkmark") }
                        .secondaryAction()
                    Button { app.decide(.scam, on: alert.id) } label: { WideLabel(title: "Penipuan", systemImage: "hand.raised.fill") }
                        .primaryAction(Brand.danger)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .sensoryFeedback(.success, trigger: alert.decision)
        .confirmationDialog("Tandai aman?", isPresented: $confirmSafe, titleVisibility: .visible) {
            Button("Ya, aman") { app.decide(.safe, on: alert.id) }
        } message: {
            Text("\(alert.parent.name) akan diberi tahu.")
        }
        .alert("Telepon \(alert.parent.name)", isPresented: $callInfo) {
            Button("Oke", role: .cancel) {}
        } message: {
            Text("Di HP asli, telepon Anda masuk sebagai panggilan tunggu, jadi \(alert.parent.name) bisa langsung beralih. Simulator tidak bisa menelepon.")
        }
    }

    @ViewBuilder
    private func decidedContent(_ decision: GuardianDecision) -> some View {
        let mine = decision.by == model.currentPerson
        let scam = decision.verdict == .scam
        HStack(spacing: 12) {
            Group {
                if mine {
                    Image(systemName: "paperplane.fill").foregroundStyle(Brand.teal)
                } else {
                    Avatar(person: decision.by, size: 36)
                }
            }
            .font(.title3)
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(mine ? "Terkirim ke \(alert.parent.name)" : "\(decision.by.name) sudah menjawab")
                    .font(.headline).foregroundStyle(Brand.ink)
                Text(mine ? "Anda: \(decision.verdict.pastTitle)" : "\(decision.verdict.pastTitle.capitalized). Cukup satu jawaban.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
            if !mine {
                Image(systemName: "lock.fill").foregroundStyle(Brand.ink3).accessibilityLabel("Tombol terkunci")
            }
        }
        .padding(12)
        .background(.white, in: .rect(cornerRadius: 20, style: .continuous))
        .shadow(color: Brand.ink.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .combine)

        Button {
            let url = URL(string: "tel:+620000000000")!
            openURL(url) { accepted in if !accepted { callInfo = true } }
        } label: {
            WideLabel(title: "Telepon \(alert.parent.name)", systemImage: "phone.fill")
        }
        .primaryAction(scam ? Brand.danger : Brand.teal)
    }
}

// MARK: - Pita tingkat risiko

/// Pita berwarna penuh di atas kartu: kuning untuk Waspada, merah untuk Bahaya.
struct LevelBand: View {
    let level: RiskLevel
    let callEnded: Bool
    let startedAt: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level.symbol)
            Text(level.title)
            Spacer()
            if callEnded {
                Label("Selesai", systemImage: "phone.down.fill").font(.subheadline.weight(.semibold))
            } else {
                HStack(spacing: 5) {
                    Circle().fill(level.glyph).frame(width: 7, height: 7)
                    Text(startedAt, style: .timer).monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Panggilan masih berlangsung")
            }
        }
        .font(.headline)
        .foregroundStyle(level.glyph)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(level.tint)
    }
}
