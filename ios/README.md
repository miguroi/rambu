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

Satu HP menjalankan ketiga peran lewat **mode demo** (ketuk avatar di pojok kanan atas): Ibu Ratna sebagai orang tua, Sinta dan Richard sebagai pengawas. Di produk nyata tiap orang memakai HP sendiri.

1. Sebagai Ibu Ratna, ketuk **Pilih contoh telepon** dan pilih skenario. Ada empat: petugas bank minta OTP, kabar anak kecelakaan, kurir menyuruh pasang aplikasi, dan telepon wajar dari tetangga.
2. Layar telepon simulasi muncul. Banner Rambu naik dari Mendengarkan ke Perlu dicek lalu Bahaya, setiap sekitar 5 detik sesuai potongan audio puck.
3. Ganti peran ke Sinta. Peringatan tampil di beranda, lengkap dengan kategori tanda dan kalimat penelepon yang disorot.
4. Sinta menekan **Ini penipuan**. Richard langsung melihat bahwa Sinta sudah menjawab, dan tombolnya terkunci.
5. Kembali ke Ibu Ratna: banner berubah jadi "Ini penipuan. Tutup teleponnya sekarang", dan tombol merah berdenyut.

Live Activity di Dynamic Island dan Lock Screen ikut berubah selama panggilan. Keluar ke layar utama saat telepon berjalan untuk melihatnya.

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

`RiskRules` di `Model/Domain.swift` adalah aturan tiruan (dua tanda berbeda langsung dianggap Bahaya). Backend boleh menggantinya sepenuhnya.

## Yang disimulasikan dan yang belum ada

- **Layar telepon** adalah tiruan. Di iPhone asli layar telepon milik iOS, dan Rambu tampil lewat Live Activity serta notifikasi.
- **Memutus telepon orang tua tidak mungkin di iOS.** Aplikasi pihak ketiga tidak bisa mengakhiri panggilan seluler maupun WhatsApp. Gantinya, setelah keputusan "Ini penipuan", pengawas bisa menekan **Telepon Ibu Ratna sekarang**. Kalau operator mengaktifkan panggilan tunggu, panggilan itu muncul di atas telepon penipu dan orang tua bisa langsung beralih. Perlu diuji di HP asli.
- **Live Activity** diperbarui secara lokal. Kalau app di latar belakang, pembaruan butuh push APNs dari server. Live Activity dari proses sebelumnya dibersihkan saat app dibuka.
- Belum ada: BLE nyata, push notification ke pengawas, panggilan penyelamat VoIP, akun, dan penyimpanan.

## Struktur

```
ios/
  project.yml                  konfigurasi XcodeGen
  RambuPuck/
    App/                       titik masuk + peluncur demo (RAMBU_SCENE)
    Store/AppModel.swift       satu sumber kebenaran untuk ketiga peran
    Model/                     domain, aturan risiko, skenario sintetis
    Services/                  protokol serah terima + simulasi + Live Activity
    DesignSystem/              kartu, tombol kaca, ikon tingkat, ilustrasi puck
    Features/                  Onboarding, Parent, Guardian, Common
  Shared/                      dipakai app dan widget: token merek, maskot, atribut Live Activity
  RambuPuckWidgets/            Live Activity: Lock Screen + Dynamic Island
  RambuPuckTests/              Swift Testing
  Screenshots/                 hasil scripts/screenshots.sh
```

## Desain

- Liquid Glass bawaan iOS 26 (`glassEffect`, `.glass`, `.glassProminent`) untuk kontrol dan navigasi. Isi informasi memakai kartu padat supaya mudah dibaca.
- Judul SF Pro Rounded, isi SF Pro, semuanya Dynamic Type.
- Tingkat risiko dibedakan bentuk dan teks, bukan warna saja: lingkaran untuk Aman, segitiga untuk Perlu dicek, oktagon untuk Bahaya.
- Merah dan kuning hanya dipakai untuk tingkat risiko.
- Maskot digambar ulang sebagai vektor (`Shared/Mascot.swift`) dengan enam pose. Titik kuning di dadanya selalu amber merek, bukan penanda status.
- Mode terang saja.

## Screenshot

```bash
ios/scripts/screenshots.sh
```

Skrip ini membangun app, lalu membuka setiap adegan lewat variabel `RAMBU_SCENE` (daftarnya ada di `DemoLaunch` pada `App/RambuPuckApp.swift`). `RAMBU_FAST=1` mempercepat potongan audio menjadi 0,7 detik.

Semua nama, nomor, dan percakapan di aplikasi ini fiktif.
