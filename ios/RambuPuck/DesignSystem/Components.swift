import SwiftUI

// Aturan pakai kaca (Liquid Glass) mengikuti HIG: kaca untuk kontrol dan navigasi
// yang melayang di atas konten; isi informasi memakai kartu padat supaya mudah dibaca.

// MARK: - Kartu isi

extension View {
    func card(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
            .shadow(color: Brand.ink.opacity(0.06), radius: 14, y: 6)
    }

    /// Tombol utama: kaca menonjol, cukup besar untuk pengguna 40+ (min. 56 pt).
    func primaryAction(_ tint: Color = Brand.teal) -> some View {
        self.buttonStyle(.glassProminent).controlSize(.extraLarge).tint(tint)
    }

    func secondaryAction() -> some View {
        self.buttonStyle(.glass).controlSize(.extraLarge)
    }
}

/// Isi tombol lebar penuh dengan tinggi minimum yang aman untuk jari.
struct WideLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

// MARK: - Tingkat risiko

struct LevelIcon: View {
    let level: RiskLevel
    @ScaledMetric private var size: CGFloat

    init(level: RiskLevel, size: CGFloat = 22) {
        self.level = level
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title3)
    }

    var body: some View {
        Image(systemName: level.symbol)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(level.glyph, level.tint)
            .accessibilityLabel(level.title)
    }
}

struct LevelPill: View {
    let level: RiskLevel

    var body: some View {
        HStack(spacing: 6) {
            LevelIcon(level: level, size: 15)
            Text(level.title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(level.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(level.soft, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Orang

struct Avatar: View {
    let person: Person
    var size: CGFloat = 44

    var body: some View {
        Text(person.initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(person.color.gradient))
            .accessibilityHidden(true)
    }
}

struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(people) { person in
                Avatar(person: person, size: size)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Teks

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Brand.display(.headline)).foregroundStyle(Brand.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(Brand.ink3)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Menyorot frasa pemicu di dalam kalimat, supaya pengawas bisa menilai sendiri.
struct HighlightedText: View {
    let text: String
    let phrases: [String]
    var tint: Color = Brand.danger
    var ink: Color = Brand.dangerInk

    var body: some View {
        Text(attributed).foregroundStyle(Brand.ink)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        for phrase in phrases where !phrase.isEmpty {
            var start = result.startIndex
            while start < result.endIndex, let range = result[start...].range(of: phrase, options: .caseInsensitive) {
                result[range].backgroundColor = tint.opacity(0.14)
                result[range].foregroundColor = ink
                result[range].inlinePresentationIntent = .stronglyEmphasized
                start = range.upperBound
            }
        }
        return result
    }
}

/// Satu tanda penipuan sebagai kapsul berikon. Menggantikan paragraf penjelasan.
struct SignalChip: View {
    let kind: SignalKind
    var level: RiskLevel = .danger
    /// Di atas latar berwarna risiko, kapsul memakai putih supaya tetap terlihat.
    var onTint = false

    var body: some View {
        Label(kind.title, systemImage: kind.symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(level.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(onTint ? .white : level.soft, in: .capsule)
    }
}

/// Deretan kapsul yang turun baris saat tidak muat.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap: CGFloat = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Kalimat penelepon sebagai gelembung chat, supaya langsung terbaca sebagai "yang dia ucapkan".
struct EvidenceCard: View {
    let line: TranscriptLine
    var level: RiskLevel = .danger

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.fill")
                .font(.footnote)
                .foregroundStyle(Brand.ink3)
                .frame(width: 30, height: 30)
                .background(Brand.hairline, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HighlightedText(text: line.text, phrases: line.flagged, tint: level.tint, ink: level.ink)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20,
                                                                  bottomTrailingRadius: 20, topTrailingRadius: 20,
                                                                  style: .continuous))
                    .shadow(color: Brand.ink.opacity(0.05), radius: 8, y: 3)
                HStack(spacing: 6) {
                    if let first = line.signals.first {
                        Image(systemName: first.symbol)
                        Text(first.title)
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.offset(line.offset)).monospacedDigit()
                        .foregroundStyle(Brand.ink3)
                        .accessibilityLabel("detik ke \(Int(line.offset))")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.ink)
                .padding(.horizontal, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Penelepon: \(line.text)")
    }
}

// MARK: - Progres langkah

/// Garis progres pengganti teks "Langkah 1 dari 4".
struct StepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Brand.teal : Brand.hairline)
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: 48 * CGFloat(total))
        .animation(.smooth, value: current)
        .accessibilityElement()
        .accessibilityLabel("Langkah \(current) dari \(total)")
    }
}

// MARK: - Kaca di atas latar gelap/warna

struct GlassChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.white.opacity(0.10)), in: .capsule)
    }
}

// MARK: - Kode 6 digit

struct DigitBoxes: View {
    let digits: String
    var count = 6
    var showsCursor = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                box(at: index)
                if index == count / 2 - 1 { Spacer().frame(width: 4) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(digits.isEmpty ? "Kode belum diisi" : "Kode \(digits.map(String.init).joined(separator: " "))")
    }

    private func box(at index: Int) -> some View {
        let characters = Array(digits)
        let value = index < characters.count ? String(characters[index]) : ""
        let active = showsCursor && index == min(characters.count, count - 1)
        return Text(value)
            .font(.system(.title, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Brand.teal : Brand.hairline, lineWidth: active ? 2 : 1)
            }
    }
}

// MARK: - Ilustrasi puck

/// Rambu Puck: cap putih krem di atas grip hijau, dengan port USB-C dan lampu indikator.
struct PuckIllustration: View {
    var ledColor: Color?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            func ellipse(centerY: CGFloat, width: CGFloat, height: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (w - width) / 2, y: centerY - height / 2, width: width, height: height))
            }
            func band(top: CGFloat, bottom: CGFloat, width: CGFloat) -> Path {
                Path(CGRect(x: (w - width) / 2, y: top, width: width, height: bottom - top))
            }

            // Grip hijau
            let gripW = w * 0.94, gripH = h * 0.26, gripTop = h * 0.62, gripBottom = h * 0.76
            ctx.fill(ellipse(centerY: gripBottom, width: gripW, height: gripH), with: .color(Brand.tealDeep))
            ctx.fill(band(top: gripTop, bottom: gripBottom, width: gripW), with: .color(Brand.tealDeep))
            ctx.fill(ellipse(centerY: gripTop, width: gripW, height: gripH), with: .linearGradient(
                Gradient(colors: [Brand.tealBright, Brand.teal]),
                startPoint: CGPoint(x: 0, y: gripTop - gripH / 2), endPoint: CGPoint(x: 0, y: gripTop + gripH / 2)))

            // Cap krem
            let capW = w * 0.80, capH = h * 0.30, capTop = h * 0.30, capBottom = h * 0.56
            let side = Gradient(colors: [Brand.puckCreamShade, Brand.puckCream, Brand.puckCream, Brand.puckCreamShade])
            ctx.fill(ellipse(centerY: capBottom, width: capW, height: capH), with: .linearGradient(
                side, startPoint: CGPoint(x: (w - capW) / 2, y: 0), endPoint: CGPoint(x: (w + capW) / 2, y: 0)))
            ctx.fill(band(top: capTop, bottom: capBottom, width: capW), with: .linearGradient(
                side, startPoint: CGPoint(x: (w - capW) / 2, y: 0), endPoint: CGPoint(x: (w + capW) / 2, y: 0)))
            ctx.fill(ellipse(centerY: capTop, width: capW, height: capH), with: .linearGradient(
                Gradient(colors: [.white, Brand.puckCream]),
                startPoint: CGPoint(x: 0, y: capTop - capH / 2), endPoint: CGPoint(x: 0, y: capTop + capH / 2)))

            // Port USB-C, lampu, mic
            let frontY = (capTop + capBottom) / 2 + capH / 2
            ctx.fill(Path(roundedRect: CGRect(x: w / 2 - w * 0.07, y: frontY - h * 0.03, width: w * 0.14, height: h * 0.06), cornerRadius: h * 0.03),
                     with: .color(Brand.ink.opacity(0.75)))
            let ledCenter = CGPoint(x: w / 2 + capW * 0.26, y: frontY - h * 0.02)
            let ledR = h * 0.022
            if let ledColor {
                ctx.fill(Path(ellipseIn: CGRect(x: ledCenter.x - ledR * 3, y: ledCenter.y - ledR * 3, width: ledR * 6, height: ledR * 6)),
                         with: .color(ledColor.opacity(0.25)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: ledCenter.x - ledR, y: ledCenter.y - ledR, width: ledR * 2, height: ledR * 2)),
                     with: .color(ledColor ?? Color(hex: 0xBDB6A6)))
            let micCenter = CGPoint(x: w / 2 - capW * 0.26, y: frontY - h * 0.02)
            ctx.fill(Path(ellipseIn: CGRect(x: micCenter.x - ledR * 0.8, y: micCenter.y - ledR * 0.8, width: ledR * 1.6, height: ledR * 1.6)),
                     with: .color(Brand.ink.opacity(0.6)))
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Tombol profil dan demo

/// Avatar di kanan atas: membuka Profil. Mode demo ada di dalam Profil.
struct ProfileButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showProfile = true
        } label: {
            Avatar(person: model.currentPerson, size: 30)
        }
        .accessibilityLabel("Profil \(model.currentPerson.name)")
    }
}

// MARK: - Banner gangguan

/// Satu baris peringatan kondisi perangkat, dengan tombol perbaikan kalau ada.
struct IssueBanner: View {
    let issue: SystemIssue
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var working = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: issue.symbol)
                .font(.headline)
                .foregroundStyle(Brand.signalInk)
                .frame(width: 40, height: 40)
                .background(Brand.signal, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(issue.title).font(.headline).foregroundStyle(Brand.ink)
                Text(issue.detail).font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
            if let action = issue.action {
                Button {
                    fix()
                } label: {
                    if working { ProgressView() } else { Text(action).font(.subheadline.weight(.semibold)) }
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.teal)
                .disabled(working)
            }
        }
        .padding(12)
        .background(Brand.signalSoft, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Brand.signal.opacity(0.5)) }
        .accessibilityElement(children: .combine)
    }

    private func fix() {
        switch issue {
        case .notificationsOff:
            Task {
                await model.requestNotifications()
                if !model.notificationsAuthorized, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        case .bluetoothOff, .puckDisconnected:
            working = true
            Task {
                await model.reconnectPuck()
                working = false
            }
        case .offline, .puckLowBattery:
            break
        }
    }
}

/// Semua gangguan yang sedang terjadi, ditumpuk di atas beranda.
struct IssueList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.issues.isEmpty {
            VStack(spacing: 8) {
                ForEach(model.issues) { IssueBanner(issue: $0) }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Telepon cepat ke pengawas

/// Tombol cepat menelepon pengawas. Saat ragu di tengah telepon, cukup satu ketukan.
struct QuickCallGuardians: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var callInfo: Person?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.guardians) { person in
                VStack(spacing: 10) {
                    Avatar(person: person, size: 52)
                    VStack(spacing: 1) {
                        Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                        Text(person.relation).font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .lineLimit(1)
                    Button {
                        openURL(URL(string: "tel:+620000000000")!) { accepted in if !accepted { callInfo = person } }
                    } label: {
                        Label("Telepon", systemImage: "phone.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.safe)
                    .accessibilityLabel("Telepon \(person.name)")
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                .shadow(color: Brand.ink.opacity(0.06), radius: 14, y: 6)
            }
        }
        .alert("Telepon \(callInfo?.name ?? "")", isPresented: .init(get: { callInfo != nil }, set: { if !$0 { callInfo = nil } })) {
            Button("Oke", role: .cancel) {}
        } message: {
            Text("Simulator tidak bisa menelepon. Di HP asli, telepon langsung tersambung.")
        }
    }
}

// MARK: - Indikator risiko berwarna penuh

/// Label status berwarna penuh: kuning untuk Waspada, merah untuk Bahaya.
struct RiskBadge: View {
    let level: RiskLevel
    var large = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: level.symbol)
            Text(level.title)
        }
            .font(large ? .headline : .subheadline.weight(.bold))
            .foregroundStyle(level.glyph)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 8 : 5)
            .background(level.tint, in: .capsule)
            .accessibilityElement(children: .combine)
    }
}

/// Ubin ikon berwarna penuh untuk baris daftar.
struct LevelTile: View {
    let level: RiskLevel
    @ScaledMetric private var size: CGFloat = 44

    var body: some View {
        Image(systemName: level.symbol)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(level.glyph)
            .frame(width: size, height: size)
            .background(level.tint, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel(level.title)
    }
}

// MARK: - Push Rambu

/// Tampilan push notifikasi Rambu, mengikuti banner notifikasi iOS:
/// ikon app, nama app, waktu, judul, isi, dan thumbnail maskot yang memegang rambu.
struct PushBanner: View {
    let toast: Toast

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("RambuIcon")
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("RAMBU").font(.caption.weight(.semibold)).foregroundStyle(Brand.ink3)
                    Spacer()
                    Text("sekarang").font(.caption).foregroundStyle(Brand.ink3)
                }
                Text(toast.title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(toast.body).font(.subheadline).foregroundStyle(Brand.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MascotView(pose: toast.level.mascotPose, animated: false, sign: toast.level)
                .padding(.top, 2)
                .frame(width: 54, height: 54)
                .background(toast.level.soft, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.9), in: .rect(cornerRadius: 26, style: .continuous))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notifikasi Rambu. \(toast.title). \(toast.body)")
    }
}

// MARK: - Maskot interaktif

/// Maskot yang memegang rambu hijau dan menyapa saat diketuk.
struct MascotBuddy: View {
    var sign: RiskLevel = .safe
    var onDark = false
    let greeting: String

    @State private var cheering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MascotView(pose: cheering ? .happy : sign.mascotPose, onDark: onDark, sign: sign)
            .scaleEffect(cheering && !reduceMotion ? 1.08 : 1, anchor: .bottom)
            .rotationEffect(.degrees(cheering && !reduceMotion ? -4 : 0), anchor: .bottom)
            .overlay(alignment: .topLeading) {
                if cheering {
                    Text(greeting)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white, in: .capsule)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .offset(x: -70, y: -6)
                        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .contentShape(.rect)
            .onTapGesture { cheer() }
            .sensoryFeedback(.impact(weight: .light), trigger: cheering) { _, new in new }
            .accessibilityElement()
            .accessibilityLabel("Maskot Rambu")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { cheer() }
    }

    private func cheer() {
        guard !cheering else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.5)) { cheering = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.smooth) { cheering = false }
        }
    }
}

// MARK: - Tempat foto

/// Foto yang bisa diisi belakangan. Kalau aset belum ada di katalog, ilustrasi cadangan tampil.
/// Nama slot: PhotoPuckProduct, PhotoPuckOnPhone, PhotoSpeakerCall (lihat ios/README.md).
struct PhotoSlot<Fallback: View>: View {
    let name: String
    var cornerRadius: CGFloat = 28
    @ViewBuilder var fallback: Fallback

    var body: some View {
        if let image = UIImage(named: name) {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                .accessibilityHidden(true)
        } else {
            fallback
        }
    }
}
