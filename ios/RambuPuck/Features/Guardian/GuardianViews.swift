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
                    if let alert = model.featuredAlert {
                        NavigationLink(value: alert.id) { AlertHeroCard(alert: alert) }
                            .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Yang Anda jaga")
                        ProtectedParentCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Menjaga bersama")
                        CoGuardianCard()
                    }

                    if model.featuredAlert == nil {
                        QuietState()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Brand.canvas)
            .navigationTitle("Halo, \(model.currentPerson.name)")
            .navigationDestination(for: UUID.self) { AlertDetail(alertID: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoButton() } }
        }
    }
}

private struct AlertHeroCard: View {
    let alert: FamilyAlert
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LevelIcon(level: alert.level, size: 26)
                Text(alert.level.title.uppercased())
                    .font(.caption.weight(.heavy)).tracking(1)
                    .foregroundStyle(alert.level.ink)
                Spacer()
                if !alert.callEnded {
                    HStack(spacing: 4) {
                        Circle().fill(Brand.danger).frame(width: 7, height: 7)
                        Text(alert.startedAt, style: .timer).monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.ink2)
                }
            }

            Text(alert.title)
                .font(Brand.display(.title2))
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(alert.channel.label) · \(alert.callerDetail)")
                .font(.subheadline).foregroundStyle(Brand.ink2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(alert.signals.prefix(3), id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(alert.level.ink)
                }
            }

            HStack {
                if let decision = alert.decision {
                    Label("\(decision.by == model.currentPerson ? "Anda" : decision.by.name) menandai \(decision.verdict.pastTitle)",
                          systemImage: decision.verdict == .scam ? "hand.raised.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                } else {
                    Text("Lihat kalimatnya dan putuskan")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink3)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alert.level.soft, in: .rect(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(alert.level.tint.opacity(0.45), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Buka peringatan")
    }
}

private struct ProtectedParentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Avatar(person: model.parent, size: 52)
            VStack(alignment: .leading, spacing: 4) {
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
                    Text("Tidak sedang menelepon").font(.subheadline).foregroundStyle(Brand.ink2)
                }
                Label("Puck \(model.puck.battery)% · \(model.puck.isConnected ? "terhubung" : "terputus")",
                      systemImage: model.puck.batterySymbol)
                    .font(.caption)
                    .foregroundStyle(Brand.ink3)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct CoGuardianCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let others = model.otherGuardians(than: model.currentPerson)
        HStack(alignment: .top, spacing: 14) {
            AvatarStack(people: [model.currentPerson] + others, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Anda dan \(others.map(\.name).formatted(.list(type: .and).locale(Fmt.locale)))")
                    .font(.headline).foregroundStyle(Brand.ink)
                Text("Semua menerima peringatan yang sama. Jawaban pertama yang masuk yang berlaku, jadi cukup satu orang.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct QuietState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            MascotView(pose: .rest).frame(height: 120)
            Text("Tidak ada yang perlu diputuskan")
                .font(Brand.display(.headline)).foregroundStyle(Brand.ink)
            Text("Anda akan diberi tahu kalau Rambu menemukan tanda penipuan di telepon \(model.parent.name).")
                .font(.subheadline).foregroundStyle(Brand.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
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

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Tanda yang terdeteksi")
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(alert.signals, id: \.self) { SignalRow(kind: $0, level: alert.level) }
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Kata-kata penelepon", trailing: "\(alert.evidence.count) kalimat")
                        ForEach(alert.evidence) { EvidenceCard(line: $0, level: alert.level) }
                        Label("Hanya kalimat yang memicu peringatan yang dikirim. Percakapan lengkap tetap di HP \(alert.parent.name).",
                              systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(Brand.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Penerima peringatan")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LevelIcon(level: alert.level, size: 34)
                Text(alert.level.title)
                    .font(Brand.display(.title3))
                    .foregroundStyle(alert.level.ink)
            }
            Text(alert.title)
                .font(Brand.display(.largeTitle))
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: alert.channel.symbol)
                Text("\(alert.channel.label) · \(alert.callerDetail)")
            }
            .font(.subheadline).foregroundStyle(Brand.ink2)
            HStack(spacing: 6) {
                if alert.callEnded {
                    Image(systemName: "phone.down.fill")
                    Text("Panggilan sudah selesai")
                } else {
                    Circle().fill(Brand.danger).frame(width: 8, height: 8)
                    Text("Masih berlangsung ·")
                    Text(alert.startedAt, style: .timer).monospacedDigit()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alert.level.soft, in: .rect(cornerRadius: 28, style: .continuous))
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
            if decision.by == person {
                return "Menandai \(decision.verdict.pastTitle) · \(Fmt.clock(decision.at))"
            }
            return "Tidak perlu menjawab lagi"
        }
        return "Menerima peringatan · \(Fmt.clock(alert.raisedAt))"
    }
}

/// Dua keputusan saja. "Aman" diberi konfirmasi karena menurunkan kewaspadaan orang tua;
/// "Ini penipuan" langsung terkirim karena setiap detik berarti.
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
                Text("Menurut Anda, ini penipuan?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button { confirmSafe = true } label: { WideLabel(title: "Aman", systemImage: "checkmark") }
                        .secondaryAction()
                    Button { model.decide(.scam, on: alert.id) } label: { WideLabel(title: "Ini penipuan", systemImage: "hand.raised.fill") }
                        .primaryAction(Brand.danger)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .sensoryFeedback(.success, trigger: alert.decision)
        .confirmationDialog("Tandai telepon ini aman?", isPresented: $confirmSafe, titleVisibility: .visible) {
            Button("Ya, aman") { model.decide(.safe, on: alert.id) }
        } message: {
            Text("\(alert.parent.name) akan diberi tahu bahwa Anda menganggap telepon ini aman.")
        }
        .alert("Telepon \(alert.parent.name)", isPresented: $callInfo) {
            Button("Mengerti", role: .cancel) {}
        } message: {
            Text("Di HP asli, panggilan Anda masuk sebagai panggilan tunggu di atas telepon yang sedang berlangsung, sehingga \(alert.parent.name) bisa langsung beralih ke Anda. Simulator tidak bisa menelepon.")
        }
    }

    @ViewBuilder
    private func decidedContent(_ decision: GuardianDecision) -> some View {
        let mine = decision.by == model.currentPerson
        HStack(spacing: 12) {
            Image(systemName: mine ? "paperplane.fill" : "lock.fill")
                .font(.title3)
                .foregroundStyle(mine ? Brand.teal : Brand.ink2)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(mine ? "Terkirim ke \(alert.parent.name)" : "\(decision.by.name) sudah menjawab lebih dulu")
                    .font(.headline).foregroundStyle(Brand.ink)
                Text(mine
                     ? "Anda menandai \(decision.verdict.pastTitle) · \(Fmt.clock(decision.at))"
                     : "Keputusannya: \(decision.verdict.pastTitle). Tombol dikunci karena jawaban pertama sudah masuk.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)

        Button {
            let url = URL(string: "tel:+620000000000")!
            openURL(url) { accepted in if !accepted { callInfo = true } }
        } label: {
            WideLabel(title: "Telepon \(alert.parent.name) sekarang", systemImage: "phone.fill")
        }
        .primaryAction(decision.verdict == .scam ? Brand.danger : Brand.teal)
    }
}
