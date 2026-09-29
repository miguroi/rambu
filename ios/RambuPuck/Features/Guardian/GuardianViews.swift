import SwiftUI

struct GuardianRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.guardianTab) {
            Tab("Beranda", systemImage: "house.fill", value: GuardianTab.home) {
                GuardianHome()
            }
            Tab("Riwayat", systemImage: "clock.fill", value: GuardianTab.history) {
                NavigationStack { HistoryList(forGuardian: true) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct GuardianHome: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.guardianPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    IssueList()
                    if let alert = model.featuredAlert {
                        NavigationLink(value: alert.id) { AlertHeroCard(alert: alert) }
                            .buttonStyle(.plain)
                    } else {
                        QuietState()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Yang Anda jaga")
                        ProtectedParentCard()
                        ForEach(model.extraParents) { OtherParentRow(person: $0) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Brand.canvas)
            .navigationTitle("Halo, \(model.currentPerson.name)")
            .navigationDestination(for: UUID.self) { AlertDetail(alertID: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        }
    }
}

private struct AlertHeroCard: View {
    let alert: FamilyAlert
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LevelBand(level: alert.level, callEnded: alert.callEnded, startedAt: alert.startedAt)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(Brand.display(.title2))
                            .foregroundStyle(Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(alert.callerDetail, systemImage: alert.channel.symbol)
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    Spacer(minLength: 0)
                    MascotView(pose: alert.level.mascotPose, sign: alert.level)
                        .frame(width: 70)
                }

                FlowLayout(spacing: 6) {
                    ForEach(alert.signals, id: \.self) { SignalChip(kind: $0, level: alert.level, onTint: true) }
                }

                HStack {
                    if let decision = alert.decision {
                        Label("\(decision.by == model.currentPerson ? "Anda" : decision.by.name): \(decision.verdict.pastTitle)",
                              systemImage: decision.verdict == .scam ? "hand.raised.fill" : "checkmark.circle.fill")
                    } else {
                        Text("Lihat dan putuskan")
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Brand.ink3)
                }
                .font(.headline)
                .foregroundStyle(Brand.ink)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alert.level.soft)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .shadow(color: alert.level.tint.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Buka peringatan")
    }
}

/// Pita berwarna penuh di atas kartu: kuning untuk Waspada, merah untuk Bahaya.
private struct LevelBand: View {
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

/// Orang tua yang dijaga plus rekan pengawas, dalam satu kartu.
/// Orang tua lain yang dijaga. Di demo tidak ada telepon dari HP mereka.
private struct OtherParentRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 14) {
            Avatar(person: person, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                Text("\(person.relation), tidak menelepon").font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.shield.fill").foregroundStyle(Brand.safe)
                .accessibilityLabel("Dijaga")
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct ProtectedParentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let others = model.otherGuardians(than: model.currentPerson)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(person: model.parent, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.parent.name).font(.headline).foregroundStyle(Brand.ink)
                    if model.session != nil {
                        Label {
                            Text("Sedang menelepon")
                        } icon: {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.teal)
                    } else {
                        Text("Tidak menelepon").font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                }
                Spacer(minLength: 0)
                Label("\(model.puck.battery)%", systemImage: model.puck.batterySymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.ink3)
                    .accessibilityLabel("Baterai puck \(model.puck.battery) persen")
            }

            Divider()

            HStack(spacing: 10) {
                AvatarStack(people: [model.currentPerson] + others, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bersama \(others.map(\.name).formatted(.list(type: .and).locale(Fmt.locale)))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                    Text("Cukup satu yang menjawab")
                        .font(.footnote).foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct QuietState: View {
    var body: some View {
        HStack(spacing: 16) {
            MascotBuddy(sign: .safe, greeting: "Aman terkendali")
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text("Semua tenang")
                    .font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                Text("Anda dikabari kalau ada tanda penipuan.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.safeSoft, in: .rect(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Detail peringatan

struct AlertDetail: View {
    let alertID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        if let alert = model.alerts.first(where: { $0.id == alertID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AlertHeader(alert: alert)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Kata penelepon")
                        ForEach(alert.evidence) { EvidenceCard(line: $0, level: alert.level) }
                        Label("Hanya kalimat ini yang dikirim", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(Brand.ink3)
                            .padding(.leading, 40)
                    }

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
                    MascotView(pose: alert.level.mascotPose, sign: alert.level)
                        .frame(width: 76)
                }
                FlowLayout(spacing: 6) {
                    ForEach(alert.signals, id: \.self) { SignalChip(kind: $0, level: alert.level, onTint: true) }
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
    @Environment(AppModel.self) private var model

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

/// Dua keputusan saja. "Aman" diberi konfirmasi karena menurunkan kewaspadaan orang tua;
/// "Penipuan" langsung terkirim karena setiap detik berarti.
private struct DecisionBar: View {
    let alert: FamilyAlert
    @Environment(AppModel.self) private var model
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
                    Button { model.decide(.scam, on: alert.id) } label: { WideLabel(title: "Penipuan", systemImage: "hand.raised.fill") }
                        .primaryAction(Brand.danger)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .sensoryFeedback(.success, trigger: alert.decision)
        .confirmationDialog("Tandai aman?", isPresented: $confirmSafe, titleVisibility: .visible) {
            Button("Ya, aman") { model.decide(.safe, on: alert.id) }
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
