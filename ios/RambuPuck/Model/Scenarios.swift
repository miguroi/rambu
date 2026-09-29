import Foundation

// Percakapan sintetis berbahasa Indonesia untuk simulasi.
// Semua nama lembaga, nomor, dan orang fiktif. Nomor penelepon sengaja disamarkan.

extension Scenario {
    static let bankOTP = Scenario(
        id: "bank-otp",
        title: "Mengaku petugas Bank Sentosa",
        summary: "Petugas bank palsu meminta kode OTP dengan alasan membatalkan transaksi.",
        callerName: "Nomor tidak dikenal",
        callerDetail: "+62 812-••••-4417",
        channel: .cellular,
        lines: [
            .init(id: 0, offset: 0, speaker: .caller,
                  text: "Selamat siang, dengan Ibu Ratna? Saya Andi dari bagian keamanan Bank Sentosa.",
                  flagged: ["dari bagian keamanan Bank Sentosa"], signals: [.impersonation]),
            .init(id: 1, offset: 5, speaker: .parent,
                  text: "Iya, betul. Ada apa, Pak?", flagged: [], signals: []),
            .init(id: 2, offset: 10, speaker: .caller,
                  text: "Ada transaksi mencurigakan di rekening Ibu. Kalau tidak dibatalkan dalam sepuluh menit, saldo Ibu bisa terkuras.",
                  flagged: ["dalam sepuluh menit", "saldo Ibu bisa terkuras"], signals: [.urgency]),
            .init(id: 3, offset: 15, speaker: .parent,
                  text: "Aduh, terus saya harus bagaimana?", flagged: [], signals: []),
            .init(id: 4, offset: 20, speaker: .caller,
                  text: "Sebentar lagi masuk SMS berisi kode enam angka. Tolong bacakan kodenya ke saya supaya transaksinya bisa saya batalkan.",
                  flagged: ["bacakan kodenya ke saya"], signals: [.secretCode]),
            .init(id: 5, offset: 25, speaker: .caller,
                  text: "Kodenya jangan diberikan ke siapa pun selain saya, ya, Bu.",
                  flagged: ["jangan diberikan ke siapa pun selain saya"], signals: [.secretCode]),
        ]
    )

    static let accidentTransfer = Scenario(
        id: "kecelakaan-transfer",
        title: "Kabar anak kecelakaan",
        summary: "Mengaku perawat, mengabarkan kecelakaan, lalu meminta transfer biaya operasi.",
        callerName: "Nomor tidak dikenal",
        callerDetail: "+62 857-••••-2290",
        channel: .whatsapp,
        lines: [
            .init(id: 0, offset: 0, speaker: .caller,
                  text: "Halo, Bu. Saya perawat dari RS Medika Utama. Anak Ibu baru saja kecelakaan motor.",
                  flagged: ["perawat dari RS Medika Utama", "Anak Ibu baru saja kecelakaan"], signals: [.impersonation]),
            .init(id: 1, offset: 5, speaker: .parent,
                  text: "Astaga, anak saya yang mana? Bagaimana keadaannya?", flagged: [], signals: []),
            .init(id: 2, offset: 10, speaker: .caller,
                  text: "Harus dioperasi sekarang juga, Bu. Kalau terlambat bisa fatal.",
                  flagged: ["dioperasi sekarang juga", "Kalau terlambat bisa fatal"], signals: [.urgency]),
            .init(id: 3, offset: 15, speaker: .caller,
                  text: "Uang mukanya delapan juta. Tolong transfer sekarang ke rekening dokter yang saya kirim.",
                  flagged: ["transfer sekarang ke rekening dokter"], signals: [.transfer]),
            .init(id: 4, offset: 20, speaker: .parent,
                  text: "Sebentar, saya telepon anak saya dulu.", flagged: [], signals: []),
            .init(id: 5, offset: 25, speaker: .caller,
                  text: "Jangan ditutup, Bu. Waktunya tidak cukup.",
                  flagged: ["Jangan ditutup", "Waktunya tidak cukup"], signals: [.urgency]),
        ]
    )

    static let courierApp = Scenario(
        id: "kurir-aplikasi",
        title: "Kurir menyuruh buka file",
        summary: "Mengaku kurir, lalu menyuruh membuka file dan memasang aplikasi untuk cek resi.",
        callerName: "Nomor tidak dikenal",
        callerDetail: "+62 896-••••-1043",
        channel: .whatsapp,
        lines: [
            .init(id: 0, offset: 0, speaker: .caller,
                  text: "Permisi, Bu. Saya kurir. Ada paket atas nama Ibu Ratna yang tertahan di gudang.",
                  flagged: ["paket atas nama Ibu Ratna yang tertahan"], signals: [.impersonation]),
            .init(id: 1, offset: 5, speaker: .parent,
                  text: "Paket apa, ya? Saya tidak pesan apa-apa.", flagged: [], signals: []),
            .init(id: 2, offset: 10, speaker: .caller,
                  text: "Untuk cek resinya, Ibu buka file yang barusan saya kirim di WhatsApp, lalu pasang aplikasinya.",
                  flagged: ["buka file yang barusan saya kirim", "pasang aplikasinya"], signals: [.remoteApp]),
            .init(id: 3, offset: 15, speaker: .caller,
                  text: "Kalau tidak dikonfirmasi hari ini, paketnya dikembalikan dan Ibu kena denda.",
                  flagged: ["tidak dikonfirmasi hari ini", "Ibu kena denda"], signals: [.urgency]),
        ]
    )

    static let neighbourSafe = Scenario(
        id: "tetangga-aman",
        title: "Telepon dari Bu Wati",
        summary: "Tetangga mengabarkan jadwal arisan. Tidak ada tanda penipuan.",
        callerName: "Bu Wati",
        callerDetail: "Kontak tersimpan",
        channel: .cellular,
        lines: [
            .init(id: 0, offset: 0, speaker: .caller,
                  text: "Assalamualaikum, Bu Ratna. Ini Wati, tetangga sebelah.", flagged: [], signals: []),
            .init(id: 1, offset: 5, speaker: .parent,
                  text: "Waalaikumsalam, Bu Wati. Ada apa?", flagged: [], signals: []),
            .init(id: 2, offset: 10, speaker: .caller,
                  text: "Arisan minggu depan jadi di rumah saya, ya. Jam empat sore.", flagged: [], signals: []),
            .init(id: 3, offset: 15, speaker: .parent,
                  text: "Oh iya, nanti saya bawa kue.", flagged: [], signals: []),
        ]
    )

    static let all: [Scenario] = [.bankOTP, .accidentTransfer, .courierApp, .neighbourSafe]

    /// Mengganti nama contoh di transkrip dengan nama orang tua yang diisi saat onboarding.
    func personalized(parentName: String) -> Scenario {
        let sample = Person.ratna.name
        guard parentName != sample else { return self }
        let swap = { (s: String) in
            s.replacingOccurrences(of: sample, with: parentName)
             .replacingOccurrences(of: "Bu Ratna", with: parentName)
        }
        let lines = lines.map {
            TranscriptLine(id: $0.id, offset: $0.offset, speaker: $0.speaker,
                           text: swap($0.text), flagged: $0.flagged.map(swap), signals: $0.signals)
        }
        return Scenario(id: id, title: title, summary: summary, callerName: callerName,
                        callerDetail: callerDetail, channel: channel, lines: lines)
    }
}

extension CallRecord {
    /// Riwayat awal supaya layar riwayat tidak kosong saat demo pertama.
    static func seed(now: Date = .now, decider: Person = .richard) -> [CallRecord] {
        [
            CallRecord(
                id: UUID(),
                title: "Telepon dari Bu Wati",
                callerDetail: "Kontak tersimpan",
                channel: .cellular,
                startedAt: now.addingTimeInterval(-26 * 3600),
                duration: 184,
                level: .safe,
                signals: [],
                evidence: [],
                decision: nil
            ),
            CallRecord(
                id: UUID(),
                title: "Hadiah undian dari nomor asing",
                callerDetail: "+62 813-••••-0921",
                channel: .whatsapp,
                startedAt: now.addingTimeInterval(-3 * 86400 - 5400),
                duration: 96,
                level: .danger,
                signals: [.impersonation, .transfer],
                evidence: [
                    TranscriptLine(id: 0, offset: 4, speaker: .caller,
                                   text: "Selamat, Ibu terpilih sebagai pemenang undian dari toko online kami.",
                                   flagged: ["terpilih sebagai pemenang undian"], signals: [.impersonation]),
                    TranscriptLine(id: 1, offset: 31, speaker: .caller,
                                   text: "Hadiahnya bisa dicairkan setelah Ibu transfer biaya pajak lima ratus ribu.",
                                   flagged: ["transfer biaya pajak"], signals: [.transfer]),
                ],
                decision: GuardianDecision(by: decider, verdict: .scam, at: now.addingTimeInterval(-3 * 86400 - 5340))
            ),
        ]
    }
}
