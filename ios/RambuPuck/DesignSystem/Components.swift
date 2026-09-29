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

struct SignalRow: View {
    let kind: SignalKind
    var level: RiskLevel = .danger
    var showHint = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(level.ink)
                .frame(width: 38, height: 38)
                .background(level.soft, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.body.weight(.semibold)).foregroundStyle(Brand.ink)
                if showHint {
                    Text(kind.hint).font(.subheadline).foregroundStyle(Brand.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EvidenceCard: View {
    let line: TranscriptLine
    var level: RiskLevel = .danger

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(line.speaker.label, systemImage: "person.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.ink3)
                Spacer()
                Text(Fmt.offset(line.offset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Brand.ink3)
                    .accessibilityLabel("Detik ke \(Int(line.offset))")
            }
            HighlightedText(text: line.text, phrases: line.flagged, tint: level.tint, ink: level.ink)
                .font(.body)
            if let first = line.signals.first {
                Label(first.title, systemImage: first.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(level.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(level.soft, in: .capsule)
            }
        }
        .card(padding: 16)
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

// MARK: - Tombol mode demo

struct DemoButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showDemoSheet = true
        } label: {
            Avatar(person: model.currentPerson, size: 30)
        }
        .accessibilityLabel("Mode demo, sedang sebagai \(model.currentPerson.name). Ketuk untuk ganti peran.")
    }
}
