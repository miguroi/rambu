import SwiftUI

struct ParentRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.parentTab) {
            Tab("Beranda", systemImage: "house.fill", value: ParentTab.home) {
                ParentHome()
            }
            Tab("Riwayat", systemImage: "clock.fill", value: ParentTab.history) {
                NavigationStack { HistoryList(forGuardian: false) }
            }
            Tab("Puck", systemImage: "circle.circle.fill", value: ParentTab.puck) {
                PuckScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: $model.isCallScreenPresented) {
            CallScreen()
        }
    }
}

struct ParentHome: View {
    @Environment(AppModel.self) private var model
    @State private var showScenarios = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ProtectionHero()
                    DemoCallCard { showScenarios = true }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Ragu? Telepon dulu")
                        GuardiansCard()
                    }

                    if let last = model.history.first {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Peringatan terakhir")
                            NavigationLink(value: last.id) {
                                HistoryRow(record: last, forGuardian: false).card(padding: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Brand.canvas)
            .navigationTitle("Halo, \(model.parent.name)")
            .navigationDestination(for: UUID.self) { CallDetail(recordID: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoButton() } }
            .sheet(isPresented: $showScenarios) { ScenarioPicker() }
        }
    }
}

private struct ProtectionHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let showMascot = !typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.puck.isConnected ? "Aktif" : "Puck terputus",
                          systemImage: model.puck.isConnected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xA8F5DC))
                    Text("Rambu siap mendengarkan")
                        .font(Brand.display(.title2))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showMascot {
                    MascotBuddy(sign: .safe, onDark: true, greeting: "Saya ikut berjaga")
                        .frame(width: 92)
                }
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassChip(systemImage: model.puck.batterySymbol, text: "Puck \(model.puck.battery)%")
                    GlassChip(systemImage: "person.2.fill", text: "\(model.guardians.count) pengawas")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 220)
                .offset(x: 80, y: -110)
                .accessibilityHidden(true)
        }
        .background(Brand.hero, in: .rect(cornerRadius: 28, style: .continuous))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .shadow(color: Brand.teal.opacity(0.3), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// Tombol cepat menelepon pengawas. Saat ragu di tengah telepon, cukup satu ketukan.
private struct GuardiansCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var callInfo: Person?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.guardians) { person in
                VStack(spacing: 10) {
                    Avatar(person: person, size: 52)
                    VStack(spacing: 1) {
                        Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                        Text(person.relation).font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .lineLimit(1)
                    Button {
                        openURL(URL(string: "tel:+620000000000")!) { accepted in if !accepted { callInfo = person } }
                    } label: {
                        Label("Telepon", systemImage: "phone.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.safe)
                    .accessibilityLabel("Telepon \(person.name)")
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                .shadow(color: Brand.ink.opacity(0.06), radius: 14, y: 6)
            }
        }
        .alert("Telepon \(callInfo?.name ?? "")", isPresented: .init(get: { callInfo != nil }, set: { if !$0 { callInfo = nil } })) {
            Button("Oke", role: .cancel) {}
        } message: {
            Text("Simulator tidak bisa menelepon. Di HP asli, telepon langsung tersambung.")
        }
    }
}

private struct DemoCallCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "phone.badge.waveform.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.teal)
                    .frame(width: 48, height: 48)
                    .background(Brand.tealSoft, in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coba simulasi telepon").font(.headline).foregroundStyle(Brand.ink)
                    Text("4 contoh percakapan").font(.subheadline).foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink3)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}
