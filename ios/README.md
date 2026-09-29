# Rambu Puck · iOS (frontend)

Aplikasi iPhone untuk Rambu Puck, PopSocket bermikrofon yang mendengarkan telepon loudspeaker orang tua lalu meneruskan tanda penipuan ke keluarga. Folder ini berisi frontend saja. Puck, transkripsi, analisis AI, dan pengiriman antarponsel masih simulasi dengan data sintetis, dan dibatasi tiga protokol supaya tim backend bisa menggantinya tanpa menyentuh UI.

Kebutuhan produk ada di [`docs/prd/rambu-puck.prd.md`](../docs/prd/rambu-puck.prd.md).

## Menjalankan

Butuh Xcode 26 dengan SDK iOS 26. Proyek Xcode sudah ikut di-commit, jadi XcodeGen hanya perlu kalau `project.yml` diubah.

```bash
open ios/RambuPuck.xcodeproj
```

Pilih simulator iPhone 17 Pro (punya Dynamic Island), lalu Run. Dari terminal:

```bash
cd ios && xcodebuild -scheme RambuPuck -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Setelah mengubah `project.yml`:

```bash
brew install xcodegen && cd ios && xcodegen generate
```

## Alur demo

Satu HP menjalankan ketiga peran lewat **Mode demo** (ketuk avatar di kanan atas, lalu Mode demo di Profil): Ibu Ratna sebagai orang tua, Sinta dan Richard sebagai pengawas. Di produk nyata tiap orang memakai HP sendiri.

1. Onboarding orang tua: tutorial tiga kartu bersuara, nama, pasang puck, persetujuan (sekaligus izin notifikasi), undangan lewat WhatsApp, lalu latihan mengetuk push.
2. Onboarding pengawas: kode (atau tautan undangan), nama dan hubungan, lalu latihan memutuskan satu contoh peringatan.
3. Di beranda orang tua, ketuk **Coba simulasi telepon**. Layar telepon polos seperti app Telepon atau WhatsApp. Rambu hanya muncul lewat push dari atas dan Live Activity. Telepon aman tidak memunculkan apa pun.
4. Ketuk push untuk membuka **Status telepon**: satu instruksi besar, jawaban pengawas, dan tombol telepon anak.
5. Ganti peran ke Sinta, buka peringatan, lalu tekan **Penipuan**. Richard melihat tombolnya terkunci. Ibu Ratna menerima push "Sinta: ini penipuan. Tutup telepon sekarang."
6. Kalau tidak ada yang menjawab dalam 45 detik (8 detik dengan `RAMBU_FAST=1`), orang tua menerima push "Belum ada jawaban. Jangan lakukan tindakan apa pun dulu."

Di Mode demo ada **Simulasi gangguan**: loudspeaker mati di telepon berikutnya, internet putus, Bluetooth mati, puck terputus, dan baterai lemah.

Semua data (nama, pengawas, riwayat, pengaturan) tersimpan lokal di `Application Support/Rambu/state.json`. Tidak ada akun.

## Batas serah terima ke backend

Semua ada di `RambuPuck/Services/Services.swift`. UI hanya mengenal protokol ini.

| Protokol | Tugas | Simulasi sekarang | Implementasi nyata |
|---|---|---|---|
| `CallAnalysisSource` | Mengalirkan `ChunkAssessment` per potongan audio ±5 detik | `ScenarioAnalysis` memutar skenario di `Model/Scenarios.swift` | Audio puck → `POST /transcribe` (lihat `backend/`) → analisis Langflow |
| `FamilyRelay` | Menyebar `FamilyAlert` ke semua pengawas dan menerima `GuardianDecision` | `LocalFamilyRelay` di memori | Server + push. **Wajib** menegakkan aturan keputusan pertama yang berlaku. |
| `PuckLink` | Menemukan dan menghubungkan puck | `SimulatedPuckLink` | CoreBluetooth, menunggu spesifikasi GATT dari tim hardware |

Kontrak data yang diharapkan UI:

- `ChunkAssessment.level` adalah tingkat **keseluruhan** panggilan dan tidak boleh turun. Nilainya `safe`, `review`, atau `danger`.
- `ChunkAssessment.signals` hanya berisi tanda di potongan itu: `impersonation`, `urgency`, `secretCode`, `transfer`, `remoteApp`.
- `TranscriptLine.flagged` berisi frasa persis dari `text` yang akan disorot untuk pengawas.
- `TranscriptLine.speaker` membedakan penelepon dari orang tua. Pengawas hanya menerima kalimat penelepon yang memicu peringatan (lihat `AppModel.makeAlert`). Ini butuh pemisahan suara dari satu mikrofon puck.
- Tingkat Aman tidak pernah dikirim ke pengawas.

### Aturan jawaban pertama di server

Dua pengawas bisa menekan hampir bersamaan, jadi keputusan harus dikunci di server dengan update atomik:

```sql
UPDATE alerts
SET decision = :verdict, decided_by = :member_id, decided_at = now()
WHERE id = :alert_id AND decision IS NULL;
```

Kalau tidak ada baris yang berubah, balas `409` dengan keputusan yang sudah ada. App memetakan ini ke `DecisionOutcome.alreadyDecided`, mengunci tombol, dan memberi tahu "Richard sudah menjawab lebih dulu". Pemenang memicu push ke orang tua dan pengawas lain.

### Lainnya untuk backend

- **Ringkasan kejadian** (`CallRecord.incidentSummary`) sekarang disusun lokal dari tanda dan keputusan. Di produk nyata teks ini dibuat watsonx Orchestrate setelah panggilan selesai dan dikirim bersama riwayat.
- **Umpan balik deteksi**: jawaban "Aman" dari pengawas dilaporkan lewat `DetectionFeedback` sebagai false positive untuk memperbaiki model Langflow. Nyata: `POST /feedback`.
- **Eskalasi tanpa jawaban** berjalan di app untuk prototipe. Di produk nyata sebaiknya timer di server supaya tetap jalan walau HP orang tua sibuk.
- **Tautan undangan**: `InviteLink` membuat tautan `https://rambu-saku.vercel.app/gabung?kode=482913` (bisa diketuk di WhatsApp). Halaman itu perlu meneruskan ke `rambu://gabung?kode=…` atau dijadikan Universal Link dengan file `apple-app-site-association`. Skema `rambu://` sudah terdaftar di app. Uji dengan `xcrun simctl openurl booted "rambu://gabung?kode=482913"`.
- **Pengingat loudspeaker**: di awal telepon (`CXCallObserver`), app menyuruh puck mengukur volume ±5 detik. Kalau terlalu pelan, app mengirim push lokal "Nyalakan loudspeaker". iOS tidak memberi tahu ke mana suara telepon app lain diarahkan, jadi pengukuran harus lewat puck. App tetap hidup di background karena mode `bluetooth-central`.

`RiskRules` di `Model/Domain.swift` adalah aturan tiruan (dua tanda berbeda langsung dianggap Bahaya). Backend boleh menggantinya sepenuhnya.

## Yang disimulasikan dan yang belum ada

- **Layar telepon** adalah tiruan. Di iPhone asli layar telepon milik iOS, dan Rambu tampil lewat Live Activity serta notifikasi.
- **Memutus telepon orang tua tidak mungkin di iOS.** Aplikasi pihak ketiga tidak bisa mengakhiri panggilan seluler maupun WhatsApp. Gantinya, setelah keputusan "Ini penipuan", pengawas bisa menekan **Telepon Ibu Ratna sekarang**. Kalau operator mengaktifkan panggilan tunggu, panggilan itu muncul di atas telepon penipu dan orang tua bisa langsung beralih. Perlu diuji di HP asli.
- **Live Activity** diperbarui secara lokal. Kalau app di latar belakang, pembaruan butuh push APNs dari server. Live Activity dari proses sebelumnya dibersihkan saat app dibuka.
- Belum ada: BLE nyata, push APNs dari server, panggilan penyelamat VoIP, dan akun. Push di prototipe memakai notifikasi lokal; kalau izin ditolak, tiruan banner muncul di dalam app.

## Struktur

```
ios/
  project.yml                        konfigurasi XcodeGen (jalankan `xcodegen` setelah menambah file)
  RambuPuck/
    App/RambuPuckApp.swift           titik masuk, RootView, peluncur demo (RAMBU_SCENE)
    Store/AppModel.swift             satu sumber kebenaran: panggilan, peringatan, keputusan, profil, penyimpanan
    Model/Domain.swift               tipe domain, aturan risiko tiruan, ringkasan kejadian
    Model/Scenarios.swift            percakapan sintetis dan riwayat awal
    Services/Services.swift          protokol serah terima ke backend + simulasi + Live Activity
    Services/Notifier.swift          push lokal (pengganti APNs di prototipe)
    Services/Support.swift           penyimpanan lokal, narasi suara, internet, tautan undangan, umpan balik
    DesignSystem/
      Components.swift               kartu, tombol, avatar, header, kode 6 digit, PhotoSlot
      RiskViews.swift                ikon, label, dan chip tingkat risiko; gelembung kalimat penelepon
      PushBanner.swift               tampilan push Rambu
      Illustrations.swift            ilustrasi puck, maskot interaktif
    Features/
      Onboarding/                    alur, jalur orang tua, jalur pengawas, tutorial, latihan
      Parent/                        beranda, layar telepon, Status telepon, Puck
      Guardian/                      beranda pengawas, detail peringatan
      Profile/                       profil, undangan, jaga orang tua lain
      Common/                        riwayat, Mode demo, banner gangguan, telepon cepat, tiruan push
  Shared/                            dipakai app dan widget: token merek, maskot, atribut Live Activity
  RambuPuckWidgets/                  Live Activity: Lock Screen + Dynamic Island
  RambuPuckTests/                    Swift Testing
  Screenshots/                       hasil scripts/screenshots.sh
```

Setiap file berisi satu layar atau satu kelompok komponen. Tipe `private` dipakai untuk bagian yang hanya dipakai di file itu.

## Desain

- Liquid Glass bawaan iOS 26 (`glassEffect`, `.glass`, `.glassProminent`) untuk kontrol dan navigasi. Isi informasi memakai kartu padat supaya mudah dibaca.
- Judul SF Pro Rounded, isi SF Pro, semuanya Dynamic Type.
- Tingkat risiko dibedakan bentuk dan teks, bukan warna saja: lingkaran untuk Aman, segitiga untuk Perlu dicek, oktagon untuk Bahaya.
- Merah dan kuning hanya dipakai untuk tingkat risiko.
- Maskot digambar ulang sebagai vektor (`Shared/Mascot.swift`) dengan enam pose. Titik kuning di dadanya selalu amber merek, bukan penanda status.
- Mode terang saja.

## Foto dan slot gambar

Foto asli dari Pexels (lisensi Pexels, bebas dipakai termasuk komersial):

- `PhotoWelcome`: ibu usia sekitar 40 menelepon dengan cemas di rumah. Foto oleh RDNE Stock project.
- `PhotoGuardian`: perempuan melihat HP. Foto oleh Tia Rahayu.

Gambar produk dan gaya hidup dibuat dengan image generation (puck belum punya foto fisik). Kalau asetnya dihapus, `PhotoSlot` menampilkan ilustrasi cadangan:

| Slot | Dipakai di | Ukuran |
|---|---|---|
| `PhotoPuckProduct` | Langkah pasang puck, tab Puck | 1600 × 1000 |
| `PhotoPuckOnPhone` | Tutorial kartu 1 | 1400 × 1400 |
| `PhotoSpeakerCall` | Tutorial kartu 2 | 1400 × 1400 |

## Screenshot

```bash
ios/scripts/screenshots.sh
```

Skrip ini membangun app, lalu membuka setiap adegan lewat variabel `RAMBU_SCENE` (daftarnya ada di `DemoLaunch` pada `App/RambuPuckApp.swift`). `RAMBU_FAST=1` mempercepat potongan audio menjadi 0,7 detik.

Semua nama, nomor, dan percakapan di aplikasi ini fiktif.
