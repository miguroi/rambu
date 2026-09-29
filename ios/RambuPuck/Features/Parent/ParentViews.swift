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
                    SpeakerReminder()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Pengawas Anda", trailing: "\(model.guardians.count) orang")
                        GuardiansCard()
                    }

                    if let last = model.history.first {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Terakhir diperiksa")
                            NavigationLink(value: last.id) {
                                HistoryRow(record: last, forGuardian: false).card(padding: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DemoCallCard { showScenarios = true }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: 0x7CF0C9)).frame(width: 8, height: 8)
                        Text(model.puck.isConnected ? "Perlindungan aktif" : "Puck belum terhubung")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text("Rambu Puck siap mendengarkan")
                        .font(Brand.display(.title2))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Setiap telepon yang memakai loudspeaker akan diperiksa.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showMascot {
                    MascotView(pose: .calm, onDark: true)
                        .frame(width: 86)
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
        .shadow(color: Brand.teal.opacity(0.35), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct SpeakerReminder: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.title2)
                .foregroundStyle(Brand.teal)
                .frame(width: 54, height: 54)
                .background(Brand.tealSoft, in: .rect(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Angkat, lalu nyalakan loudspeaker")
                    .font(.headline).foregroundStyle(Brand.ink)
                Text("Puck hanya bisa mendengar suara dari speaker HP.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct GuardiansCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.guardians) { person in
                HStack(spacing: 12) {
                    Avatar(person: person, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                        Text(person.relation).font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    Spacer()
                    Label("Terhubung", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.safeInk)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if person != model.guardians.last { Divider().padding(.leading, 56) }
            }
            Text("Kalau ada tanda penipuan, mereka diberi tahu bersamaan. Jawaban pertama yang masuk yang berlaku.")
                .font(.footnote)
                .foregroundStyle(Brand.ink3)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
    }
}

private struct DemoCallCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("DEMO")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(Brand.teal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Brand.tealSoft, in: .capsule)
                Text("Coba simulasi telepon").font(.headline).foregroundStyle(Brand.ink)
            }
            Text("Pilih contoh percakapan untuk melihat cara Rambu dan pengawas bekerja.")
                .font(.subheadline).foregroundStyle(Brand.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) { WideLabel(title: "Pilih contoh telepon", systemImage: "phone.arrow.down.left.fill") }
                .primaryAction()
        }
        .card()
    }
}
