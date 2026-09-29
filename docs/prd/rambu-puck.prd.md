# Rambu Puck

Pendamping anti-penipuan untuk telepon yang sedang berlangsung. Sebuah PopSocket berisi mikrofon mendengarkan suara loudspeaker di HP orang tua, lalu keluarga yang dipercaya ikut memutuskan saat ada tanda penipuan.

Dokumen ini hanya berisi kebutuhan produk. Rancangan teknis ada di rencana implementasi terpisah.

## Problem

Penipu lewat telepon, baik panggilan seluler biasa maupun panggilan WhatsApp, menyamar sebagai bank, kurir, instansi, atau kerabat, lalu mendesak korban mentransfer uang atau menyebutkan kode OTP. Orang tua berusia 40 tahun ke atas paling rentan karena keputusan harus diambil saat panggilan masih berjalan, di bawah tekanan, dan tanpa ada yang bisa ditanya. Kalau dibiarkan, kerugiannya uang yang hampir mustahil kembali, ditambah rasa malu yang membuat korban enggan bercerita ke keluarga.

Di iPhone, aplikasi apa pun tidak bisa mendengar maupun memutus panggilan yang sedang berlangsung. Karena itu pendengaran dipindahkan ke perangkat kecil di punggung HP.

## Evidence

- Laporan penipuan ke Indonesia Anti-Scam Centre (IASC) mencapai 668.441 laporan per Agustus 2026 (riset Waskita, dokumen *Waskita01RisetdanInsight*).
- Prototipe Android di repo ini sedang menguji apakah mikrofon HP bisa menangkap kedua sisi percakapan lewat loudspeaker. Target awalnya 60 sampai 70 persen kata terkenali. Hasilnya belum tercatat.
- Bahwa orang tua 40+ mau memakai puck dan menyalakan loudspeaker saat menerima telepon asing: asumsi, perlu divalidasi lewat uji prototipe dengan minimal lima orang tua.
- Bahwa anak atau kerabat bersedia menanggapi peringatan dalam hitungan detik: asumsi, perlu divalidasi lewat uji prototipe dengan pasangan orang tua dan anak.

## Users

- **Primary (dilindungi)**: orang tua usia 40 tahun ke atas yang memakai iPhone, sering menerima telepon dari nomor dikenal maupun tidak dikenal, dan tidak selalu bisa mengenali modus penipuan saat panik. Kebutuhan muncul ketika penelepon mulai meminta data, uang, atau tindakan segera.
- **Primary (pengawas)**: anak atau kerabat dewasa yang dipercaya orang tua. Satu orang tua bisa diawasi lebih dari satu pengawas sekaligus. Kebutuhan muncul saat mereka menerima peringatan dan harus menilai dalam hitungan detik apakah percakapan itu penipuan.
- **Not for**: orang yang ingin menyadap atau merekam telepon orang lain diam-diam, pengguna Android (sudah ditangani prototipe Android terpisah), dan penyaringan panggilan massal untuk perusahaan.

## Hypothesis

We believe **puck pendengar di punggung HP yang mengubah percakapan loudspeaker menjadi peringatan berbahasa Indonesia, lalu meneruskannya beserta kalimat pemicu ke pengawas keluarga** will **membuat orang tua berhenti sebelum mentransfer uang atau menyebutkan OTP** for **orang tua usia 40+ dan pengawas keluarganya**.
We'll know we're right when **dalam skenario penipuan sintetis, pengawas mengambil keputusan dan orang tua menerima keputusan itu sebelum penelepon sampai pada permintaan transfer atau OTP, pada minimal 8 dari 10 percobaan**.

## Success Metrics

| Metric | Target | How measured |
|---|---|---|
| Waktu dari kalimat pemicu diucapkan sampai peringatan tampil di HP orang tua | Paling lama 15 detik | Skenario sintetis berlabel pada jaringan uji yang terdokumentasi |
| Pengawas yang mengambil keputusan setelah peringatan tiba | Median di bawah 20 detik | Log waktu pada uji prototipe dengan pasangan orang tua dan anak |
| Kata terkenali dari rekaman loudspeaker lewat puck | 60 sampai 70 persen | Membandingkan transkrip dengan naskah yang dibacakan |
| Orang tua bisa menyebutkan alasan peringatan dengan kata-katanya sendiri | 4 dari 5 peserta | Wawancara singkat setelah uji |
| Peringatan palsu pada percakapan wajar | TBD, perlu divalidasi lewat set transkrip sah sintetis | Menjalankan transkrip percakapan normal |

## Scope

**MVP** — Satu aplikasi iPhone dengan dua peran.

Orang tua memasangkan puck, menghubungkan pengawas lewat kode, dan menerima telepon seperti biasa dengan loudspeaker menyala. Selama panggilan, status pemeriksaan terlihat di layar telepon dengan tiga tingkat: Aman, Perlu dicek, Bahaya. Penjelasannya singkat, berbahasa Indonesia, dan selalu menyebut alasannya.

Tingkat Perlu dicek dan Bahaya otomatis dikirim ke semua pengawas, lengkap dengan kategori tanda (menyamar sebagai lembaga, desakan waktu, meminta OTP atau PIN, instruksi transfer) dan kalimat pemicu yang disorot, supaya pengawas bisa menilai sendiri. Tingkat Aman tidak dikirim.

Pengawas memilih salah satu dari dua keputusan: **Ini penipuan** atau **Aman**. Keputusan pertama yang masuk berlaku. Pengawas lain langsung diberi tahu siapa yang memutuskan dan apa keputusannya, lalu tombolnya terkunci. Orang tua menerima satu hasil dan satu langkah aman.

Karena aplikasi tidak bisa memutus panggilan, keputusan "Ini penipuan" dibuat sekuat mungkin terasa oleh orang tua: status Bahaya di layar telepon, notifikasi mendesak dari pengawas yang memutuskan, dan tombol bagi pengawas untuk langsung menelepon orang tua.

Riwayat panggilan yang diperiksa tersimpan dan bisa dilihat kedua peran. Untuk Stage 1 hackathon, puck, transkripsi, dan analisis berjalan sebagai simulasi dengan data sintetis.

**Out of scope**
- Memutus panggilan orang tua secara otomatis. iOS tidak mengizinkan aplikasi mengakhiri panggilan seluler atau panggilan milik aplikasi lain.
- Perekaman tersembunyi atau tanpa persetujuan. Bertentangan dengan UU PDP No. 27 Tahun 2022 dan prinsip produk.
- Panggilan lewat headset atau Bluetooth. Puck hanya mendengar suara loudspeaker.
- Android. Sudah ada prototipe terpisah.
- Pemeriksaan pesan teks dan chat. Fokus MVP adalah telepon.
- Mode gelap. Ditunda sampai tampilan terang tervalidasi.

## Delivery Milestones

| # | Milestone | Outcome | Status | Plan |
|---|---|---|---|---|
| 1 | Prototipe iOS dengan data sintetis (Stage 1, 4 Okt 2026) | Seluruh alur orang tua dan dua pengawas bisa didemokan di simulator, termasuk keputusan pertama yang berlaku | in-progress | Rencana disetujui di percakapan |
| 2 | Transkripsi dan analisis nyata | Peringatan berasal dari transkripsi Bahasa Indonesia dan analisis Langflow, bukan skenario | pending | — |
| 3 | Tindak lanjut lewat watsonx Orchestrate | Setelah keputusan "Ini penipuan", keluarga mendapat langkah lanjutan seperti lapor ke bank atau kanal aduan resmi | pending | — |
| 4 | Puck fisik terhubung | Suara loudspeaker dari puck sungguhan sampai ke aplikasi | pending | — |
| 5 | Panggilan penyelamat dari pengawas | Pengawas bisa menelepon orang tua di atas panggilan penipu | pending | — |
| 6 | Uji bersama orang tua | Metrik keberhasilan terukur pada peserta nyata | pending | — |

## Open Questions

- [ ] Apakah iOS menampilkan pilihan "Akhiri & Terima" saat panggilan penyelamat masuk di atas panggilan seluler atau WhatsApp, atau hanya "Tahan & Terima"? Perlu diuji di iPhone asli.
- [ ] Bagaimana memisahkan suara penelepon dari suara orang tua pada satu mikrofon puck? Menentukan apakah pengawas hanya membaca kata-kata penelepon.
- [ ] Apakah puck perlu motor getar? Tanpa itu, peringatan fisik tidak sampai ke orang tua karena LED berada di punggung HP yang menghadap ke luar.
- [ ] Peran watsonx Orchestrate di alur, sebagai syarat wajib hackathon, belum diputuskan.
- [ ] Apa isi wajib submission Stage 1 menurut panitia?
- [ ] Berapa lama riwayat dan kalimat pemicu disimpan, dan siapa yang boleh menghapusnya?

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Orang tua lupa atau enggan menyalakan loudspeaker | Tinggi | Tinggi | Pengingat di aplikasi dan puck; diuji di milestone 6 |
| Kualitas suara loudspeaker terlalu rendah untuk transkripsi | Sedang | Tinggi | Hasil uji prototipe Android dan puck menentukan kelanjutan |
| Pengawas tidak menanggapi tepat waktu | Sedang | Tinggi | Lebih dari satu pengawas; langkah aman tetap tampil tanpa menunggu keputusan |
| Peringatan palsu membuat orang tua curiga pada telepon wajar | Sedang | Sedang | Tiga tingkat dengan alasan eksplisit; Aman tidak dikirim ke pengawas |
| Privasi: pengawas membaca kata-kata orang tua | Sedang | Tinggi | Hanya kalimat pemicu yang dikirim; persetujuan eksplisit saat memasangkan |
| Tenggat Stage 1 lima hari | Tinggi | Sedang | Milestone 1 memakai data sintetis; integrasi di Stage 2 |

---
*Status: DRAFT — kebutuhan produk saja. Rencana implementasi milestone 1 sudah disetujui di percakapan dan sedang dieksekusi.*
