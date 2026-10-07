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

/// Selected automatic-transcription excerpt, not a verified quote or a speaker-timed recording.
struct EvidenceCard: View {
    let line: TranscriptLine
    var level: RiskLevel = .danger

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line.text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                .font(.body).foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !line.signals.isEmpty {
                Text("Ditandai Rambu: " + line.signals.map(\.title).joined(separator: ", "))
                    .font(.caption).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Keep every stored excerpt accessible verbatim, including overlaps omitted from the short view.
struct CallEvidenceSection: View {
    let evidence: [TranscriptLine]
    let level: RiskLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Bagian yang ditandai Rambu")
            Text("Cuplikan dari transkripsi otomatis. Kata-kata bisa salah terbaca; penanda adalah hasil analisis Rambu.")
                .font(.subheadline).foregroundStyle(Brand.ink2)
            if evidence.isEmpty {
                Text("Cuplikan percakapan belum tersedia.")
                    .font(.body).foregroundStyle(Brand.ink2)
            } else {
                ForEach(TranscriptLine.groupedForDisplay(evidence)) { EvidenceCard(line: $0, level: level) }
                DisclosureGroup("Lihat transkripsi otomatis") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Semua cuplikan yang tersimpan, bukan transkripsi lengkap panggilan. Teks di bawah tidak diubah.")
                            .font(.footnote).foregroundStyle(Brand.ink2)
                        ForEach(Array(evidence.enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cuplikan \(index + 1)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Brand.ink2)
                                Text(line.text).font(.body).foregroundStyle(Brand.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .font(.subheadline).tint(Brand.teal)
            }
        }
    }
}
