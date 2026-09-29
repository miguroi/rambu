import SwiftUI

// MARK: - Tab dan beranda

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

// MARK: - Kartu beranda

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
