import SwiftUI

// Tampilan tingkat risiko. Bentuk ikon ikut membedakan tingkat (lingkaran, segitiga, oktagon),
// jadi status tetap terbaca tanpa warna.

// MARK: - Ikon dan label

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

// MARK: - Tanda dan kalimat penelepon

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
