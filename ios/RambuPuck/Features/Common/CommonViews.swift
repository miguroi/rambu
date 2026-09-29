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
                ContentUnavailableView("Belum ada riwayat", systemImage: "clock",
                                       description: Text("Panggilan yang diperiksa Rambu muncul di sini."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(records) { record in
                        NavigationLink(value: record.id) { HistoryRow(record: record, forGuardian: forGuardian) }
                    }
                } footer: {
                    Text(forGuardian
                         ? "Hanya telepon yang ditandai Perlu dicek atau Bahaya yang dibagikan ke pengawas."
                         : "Riwayat tersimpan di HP ini. Pengawas hanya melihat telepon yang ditandai.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.canvas)
        .navigationTitle("Riwayat")
        .navigationDestination(for: UUID.self) { CallDetail(recordID: $0) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoButton() } }
    }
}

struct HistoryRow: View {
    let record: CallRecord
    let forGuardian: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LevelIcon(level: record.level, size: 26)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(forGuardian ? "\(model.parent.name) · \(record.title)" : record.title)
                    .font(.headline).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Fmt.day(record.startedAt)) · \(record.channel.short) · \(Fmt.duration(record.duration))")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                if let decision = record.decision {
                    Label("\(decision.by.name): \(decision.verdict.pastTitle)",
                          systemImage: decision.verdict == .scam ? "hand.raised.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(decision.verdict == .scam ? Brand.dangerInk : Brand.safeInk)
                } else if record.level == .safe {
                    Text("Tidak ada tanda penipuan").font(.subheadline).foregroundStyle(Brand.safeInk)
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
                        LevelPill(level: record.level)
                        Text(record.title)
                            .font(Brand.display(.title))
                            .foregroundStyle(Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Fmt.day(record.startedAt)) · \(record.channel.label) · \(Fmt.duration(record.duration))")
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                        Text(record.callerDetail).font(.subheadline).foregroundStyle(Brand.ink3)
                    }

                    if let decision = record.decision {
                        HStack(spacing: 12) {
                            Avatar(person: decision.by, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(decision.by.name) menandai \(decision.verdict.pastTitle)")
                                    .font(.headline).foregroundStyle(Brand.ink)
                                Text(Fmt.day(decision.at)).font(.subheadline).foregroundStyle(Brand.ink2)
                            }
                        }
                        .card()
                    }

                    if record.signals.isEmpty {
                        HStack(spacing: 12) {
                            MascotView(pose: .calm, animated: false).frame(width: 56)
                            Text("Rambu tidak menemukan tanda penipuan di telepon ini. Telepon ini tidak dibagikan ke pengawas.")
                                .font(.body).foregroundStyle(Brand.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .card()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Tanda yang terdeteksi")
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(record.signals, id: \.self) { SignalRow(kind: $0, level: record.level) }
                            }
                            .card()
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Kata-kata penelepon")
                            ForEach(record.evidence) { EvidenceCard(line: $0, level: record.level) }
                        }
                    }
                }
                .padding(20)
            }
            .background(Brand.canvas)
            .navigationTitle("Detail telepon")
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
                    Text("Semua percakapan fiktif. Rambu memeriksa potongan suara tiap sekitar 5 detik, jadi tanda muncul bertahap.")
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
                HStack(spacing: 8) {
                    LevelPill(level: scenario.expectedLevel)
                    Text(scenario.channel.short).font(.caption).foregroundStyle(Brand.ink3)
                }
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
                    Text("Di produk nyata, setiap orang memakai HP masing-masing. Mode demo menggabungkan ketiganya di satu HP.")
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

                if !model.persona.isParent, let alert = model.alerts.first(where: { $0.decision == nil }) {
                    let other = model.otherGuardians(than: model.currentPerson).first ?? .richard
                    Section {
                        Button("\(other.name) menandai penipuan lebih dulu") {
                            model.simulateDecision(by: other, .scam, on: alert.id)
                            dismiss()
                        }
                    } header: {
                        Text("Pengawas lain")
                    } footer: {
                        Text("Untuk melihat tombol keputusan yang terkunci setelah jawaban pertama masuk.")
                    }
                }

                Section {
                    Button("Ulangi dari awal", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Semua nama, nomor, dan percakapan di aplikasi ini fiktif. Puck, transkripsi, dan pengiriman ke pengawas disimulasikan.")
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

// MARK: - Toast

struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let toast = model.toast {
                ToastCard(toast: toast)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: model.toast)
    }
}

private struct ToastCard: View {
    let toast: Toast
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Brand.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch toast {
        case .alert(let id):
            LevelIcon(level: model.alerts.first { $0.id == id }?.level ?? .review, size: 30)
        case .decision(_, let decision):
            Avatar(person: decision.by, size: 36)
        }
    }

    private var title: String {
        switch toast {
        case .alert(let id):
            model.alerts.first { $0.id == id }?.title ?? "Peringatan baru"
        case .decision(_, let decision):
            "\(decision.by.name) menandai \(decision.verdict.pastTitle)"
        }
    }

    private var subtitle: String {
        switch toast {
        case .alert: "Ketuk untuk melihat kalimatnya"
        case .decision: "Keputusan sudah dikirim ke \(model.parent.name)"
        }
    }

    private func open() {
        switch toast {
        case .alert(let id), .decision(let id, _):
            if model.persona.isParent {
                model.parentTab = .history
                model.toast = nil
            } else {
                model.openAlert(id)
            }
        }
    }
}
