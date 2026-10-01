import SwiftUI

// MARK: - Daftar riwayat

struct HistoryList: View {
    let forGuardian: Bool
    @Environment(AppState.self) private var model

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
    @Environment(AppState.self) private var model

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

/// Ikon kecil rapat dengan teks, untuk baris metadata.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.footnote)
            configuration.title
        }
    }
}

// MARK: - Detail telepon

struct CallDetail: View {
    let recordID: UUID
    @Environment(AppState.self) private var model

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
