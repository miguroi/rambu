import SwiftUI

// MARK: - Riwayat

struct HistoryList: View {
    let forGuardian: Bool
    @Environment(AppModel.self) private var model

    /// Pengawas hanya melihat panggilan yang pernah diteruskan. Panggilan Aman tetap privat.
    private var records: [CallRecord] {
        forGuardian ? model.history.filter { $0.level.relaysToGuardians } : model.history
    }

    var body: some View {
        List {
            if records.isEmpty {
                VStack(spacing: 10) {
                    MascotView(pose: .calm, sign: .safe).frame(height: 130)
                    Text("Belum ada peringatan").font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                    Text("Telepon Waspada dan Bahaya muncul di sini.")
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(records) { record in
                        NavigationLink(value: record.id) { HistoryRow(record: record, forGuardian: forGuardian) }
                    }
                } footer: {
                    Label("Hanya telepon Waspada dan Bahaya", systemImage: "lock.fill")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.canvas)
        .navigationTitle("Riwayat")
        .navigationDestination(for: UUID.self) { CallDetail(recordID: $0) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
    }
}

struct HistoryRow: View {
    let record: CallRecord
    let forGuardian: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LevelTile(level: record.level)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.headline).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RiskBadge(level: record.level)
                    Label(Fmt.day(record.startedAt), systemImage: record.channel.symbol)
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                        .labelStyle(CompactLabelStyle())
                }
                if let decision = record.decision {
                    Label("\(decision.by.name): \(decision.verdict.pastTitle)",
                          systemImage: decision.verdict == .scam ? "hand.raised.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(decision.verdict == .scam ? Brand.dangerInk : Brand.safeInk)
                        .labelStyle(CompactLabelStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct CallDetail: View {
    let recordID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        if let record = model.history.first(where: { $0.id == recordID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        RiskBadge(level: record.level, large: true)
                        Text(record.title)
                            .font(Brand.display(.title))
                            .foregroundStyle(Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Label(Fmt.day(record.startedAt), systemImage: "calendar")
                            Label(Fmt.duration(record.duration), systemImage: "timer")
                        }
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                        .labelStyle(CompactLabelStyle())
                        Label(record.callerDetail, systemImage: record.channel.symbol)
                            .font(.subheadline).foregroundStyle(Brand.ink3)
                            .labelStyle(CompactLabelStyle())
                    }

                    SummaryCard(record: record)

                    if let decision = record.decision {
                        HStack(spacing: 12) {
                            Avatar(person: decision.by, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(decision.by.name): \(decision.verdict.pastTitle)")
                                    .font(.headline).foregroundStyle(Brand.ink)
                                Text(Fmt.day(decision.at)).font(.subheadline).foregroundStyle(Brand.ink2)
                            }
                        }
                        .card()
                    }

                    if record.decision?.verdict == .safe {
                        Label("Ditandai aman. Dipakai untuk memperbaiki deteksi Rambu.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote).foregroundStyle(Brand.ink3)
                    }

                    if record.signals.isEmpty {
                        HStack(spacing: 12) {
                            MascotView(pose: .calm, animated: false).frame(width: 56)
                            Text("Tidak ada tanda penipuan. Tidak dibagikan ke pengawas.")
                                .font(.body).foregroundStyle(Brand.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .card()
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(record.signals, id: \.self) { SignalChip(kind: $0, level: record.level) }
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Kata penelepon")
                            ForEach(record.evidence) { EvidenceCard(line: $0, level: record.level) }
                        }
                    }
                }
                .padding(20)
            }
            .background(Brand.canvas)
            .navigationTitle("Detail")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Riwayat tidak ditemukan", systemImage: "clock.badge.xmark")
        }
    }
}

// MARK: - Pilih skenario

struct ScenarioPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Scenario.all) { scenario in
                        Button {
                            dismiss()
                            model.startCall(scenario)
                        } label: {
                            ScenarioRow(scenario: scenario)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Semua percakapan fiktif.")
                }
            }
            .navigationTitle("Contoh telepon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct ScenarioRow: View {
    let scenario: Scenario

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: scenario.channel.symbol)
                .font(.headline)
                .foregroundStyle(Brand.teal)
                .frame(width: 40, height: 40)
                .background(Brand.tealSoft, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title).font(.headline).foregroundStyle(Brand.ink)
                Text(scenario.summary).font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                LevelPill(level: scenario.expectedLevel)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mode demo

struct DemoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Persona.allCases) { persona in
                        Button {
                            model.switchPersona(persona)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(person: model.person(for: persona), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.person(for: persona).name).font(.headline).foregroundStyle(Brand.ink)
                                    Text(persona.roleLabel).font(.subheadline).foregroundStyle(Brand.ink2)
                                }
                                Spacer()
                                if model.persona == persona {
                                    Image(systemName: "checkmark").font(.headline).foregroundStyle(Brand.teal)
                                }
                            }
                        }
                        .accessibilityAddTraits(model.persona == persona ? .isSelected : [])
                    }
                } header: {
                    Text("Lihat sebagai")
                } footer: {
                    Text("Aslinya tiap orang memakai HP sendiri.")
                }

                if model.persona.isParent, model.onboardingComplete {
                    Section("Simulasi telepon") {
                        ForEach(Scenario.all) { scenario in
                            Button {
                                dismiss()
                                model.startCall(scenario)
                            } label: { ScenarioRow(scenario: scenario) }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle("Loudspeaker mati di telepon berikutnya", isOn: Bindable(model).speakerOffNextCall)
                    Toggle("Internet putus", isOn: Bindable(model).simulateOffline)
                    Toggle("Bluetooth menyala", isOn: Bindable(model).bluetoothOn)
                    Toggle("Puck tersambung", isOn: Binding(get: { model.puck.isConnected }, set: { model.puck.isConnected = $0 }))
                    Toggle("Baterai puck lemah", isOn: Binding(get: { model.puck.battery <= 20 },
                                                               set: { model.puck.battery = $0 ? 14 : 82 }))
                } header: {
                    Text("Simulasi gangguan")
                } footer: {
                    Text("Untuk melihat banner di beranda dan pengingat loudspeaker.")
                }
                .tint(Brand.teal)

                if !model.persona.isParent, let alert = model.alerts.first(where: { $0.decision == nil }) {
                    let other = model.otherGuardians(than: model.currentPerson).first ?? .richard
                    Section {
                        Button("\(other.name) menjawab lebih dulu") {
                            model.simulateDecision(by: other, .scam, on: alert.id)
                            dismiss()
                        }
                    } header: {
                        Text("Pengawas lain")
                    } footer: {
                        Text("Lihat tombol yang terkunci.")
                    }
                }

                Section {
                    Button("Ulangi dari awal", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Semua data di sini fiktif.")
                }
            }
            .navigationTitle("Mode demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Ulangi demo dari awal?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Ulangi", role: .destructive) {
                    model.resetDemo()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Tiruan push

/// Tiruan banner push Rambu, dipakai saat izin notifikasi belum diberikan.
/// Turun dari atas, hilang sendiri, bisa diusap ke atas, dan bisa diketuk.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        Group {
            if let toast = model.toast {
                Button { open(toast) } label: { PushBanner(toast: toast) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .offset(y: min(drag, 0))
                    .gesture(
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation.height }
                            .onEnded { value in if value.translation.height < -30 { model.toast = nil } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: model.toast)
    }

    private func open(_ toast: Toast) {
        model.openToast(toast)
    }
}

/// Ikon kecil rapat dengan teks, untuk baris metadata.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.footnote)
            configuration.title
        }
    }
}

/// Ringkasan kejadian dalam satu paragraf. Nyata: dibuat backend (watsonx Orchestrate).
private struct SummaryCard: View {
    let record: CallRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ringkasan", systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.teal)
            Text(record.incidentSummary)
                .font(.body)
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
