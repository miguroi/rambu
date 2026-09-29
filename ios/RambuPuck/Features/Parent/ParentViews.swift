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
                .sheet(isPresented: $model.showCallStatus) {
                    CallStatusView()
                        .presentationDetents([.large])
                }
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
                    IssueList()
                    ProtectionHero()
                    DemoCallCard { showScenarios = true }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Ragu? Telepon dulu")
                        QuickCallGuardians()
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
            .sheet(isPresented: $showScenarios) { ScenarioPicker() }
            .animation(.smooth, value: model.issues)
        }
    }
}

private struct ProtectionHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let showMascot = !typeSize.isAccessibilitySize
        let ready = model.puck.isConnected && model.bluetoothOn
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(ready ? "Aktif" : "Belum aktif",
                          systemImage: ready ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xA8F5DC))
                    Text(ready ? "Rambu siap mendengarkan" : "Rambu belum bisa mendengar")
                        .font(Brand.display(.title2))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showMascot {
                    MascotBuddy(sign: ready ? .safe : .review, onDark: true,
                                greeting: ready ? "Saya ikut berjaga" : "Sambungkan puck, ya")
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
