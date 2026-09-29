import SwiftUI

/// Layar yang terbuka saat orang tua mengetuk push Rambu di tengah telepon.
/// Satu instruksi besar, jawaban pengawas, dan tombol menelepon anak.
struct CallStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = model.session {
                        let status = Status(session: session, alert: model.activeAlert,
                                            unanswered: model.unanswered.contains(session.id))
                        hero(status)
                        guardiansLine(status)
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Ragu? Telepon dulu")
                            QuickCallGuardians()
                        }
                    } else {
                        ContentUnavailableView("Telepon sudah selesai", systemImage: "phone.down.fill")
                    }
                }
                .padding(20)
            }
            .background(Brand.canvas)
            .navigationTitle("Status telepon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kembali ke telepon", systemImage: "phone.fill") { dismiss() }
                }
            }
            .onAppear {
                if let session = model.session {
                    let status = Status(session: session, alert: model.activeAlert,
                                        unanswered: model.unanswered.contains(session.id))
                    model.narrate("\(status.title). \(status.detail)")
                }
            }
        }
    }

    private func hero(_ status: Status) -> some View {
        VStack(spacing: 14) {
            MascotView(pose: status.level.mascotPose, sign: status.level)
                .frame(height: 170)
            RiskBadge(level: status.level, large: true)
            Text(status.title)
                .font(Brand.display(.largeTitle))
                .foregroundStyle(Brand.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(status.detail)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(status.level.soft, in: .rect(cornerRadius: 32, style: .continuous))
    }

    private func guardiansLine(_ status: Status) -> some View {
        HStack(spacing: 12) {
            AvatarStack(people: model.guardians, size: 34)
            Text(status.guardianNote)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }

    /// Apa yang harus dilakukan orang tua sekarang, dari keadaan telepon dan jawaban pengawas.
    private struct Status {
        let level: RiskLevel
        let title: String
        let detail: String
        let guardianNote: String

        @MainActor
        init(session: CallSession, alert: FamilyAlert?, unanswered: Bool) {
            if let decision = alert?.decision {
                let scam = decision.verdict == .scam
                level = scam ? .danger : .safe
                title = scam ? "Tutup telepon sekarang" : "Aman, kata \(decision.by.name)"
                detail = scam ? "\(decision.by.name) yakin ini penipuan." : "Tetap jangan beri kode atau transfer."
                guardianNote = "\(decision.by.name) sudah menjawab."
            } else if unanswered {
                level = session.level
                title = "Belum ada jawaban"
                detail = "Jangan lakukan tindakan apa pun dulu."
                guardianNote = "Pengawas sudah diberi tahu, menunggu jawaban."
            } else if session.level > .safe {
                level = session.level
                title = session.level == .danger ? "Terindikasi penipuan" : "Telepon mencurigakan"
                detail = session.level.parentAdvice
                guardianNote = "Pengawas sudah diberi tahu, menunggu jawaban."
            } else {
                level = .safe
                title = session.speakerOn ? "Rambu ikut mendengar" : "Nyalakan loudspeaker"
                detail = session.speakerOn ? "Belum ada tanda penipuan." : "Rambu belum bisa mendengar."
                guardianNote = "Pengawas dikabari kalau ada tanda penipuan."
            }
        }
    }
}
