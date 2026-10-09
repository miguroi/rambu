import SwiftUI

/// Pose maskot. Setiap pose punya tugas, bukan sekadar hiasan:
/// wave menyapa, calm menenangkan, stop menahan saat Bahaya,
/// check memeriksa, happy merayakan keputusan, rest saat tidak aktif.
enum MascotPose: String, CaseIterable, Sendable {
    case wave, calm, stop, check, happy, rest
}

/// Maskot Rambu digambar ulang sebagai vektor dari maskot prototipe web,
/// supaya ekspresi dan posenya bisa berganti mengikuti keadaan.
/// Titik kuning di dada selalu amber merek (sama dengan titik di logo), bukan penanda status.
struct MascotView: View {
    var pose: MascotPose
    var onDark: Bool = false
    var animated: Bool = true
    /// Papan rambu yang diangkat maskot: lingkaran hijau, segitiga kuning, atau oktagon STOP merah.
    var sign: RiskLevel? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: nil)
            }
        }
        .aspectRatio(MascotArt.box(sign: sign).width / MascotArt.box(sign: sign).height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func canvas(time: TimeInterval?) -> some View {
        let pose = pose
        let sign = sign
        let palette = MascotArt.Palette(onDark: onDark)
        return Canvas { context, size in
            MascotArt.draw(pose: pose, sign: sign, palette: palette, time: time, in: &context, size: size)
        }
    }
}

enum MascotArt {
    static let size = CGSize(width: 156, height: 180)
    /// Ruang tambahan di atas dan kanan untuk papan rambu.
    private static let signInset = CGSize(width: 16, height: 36)

    static func box(sign: RiskLevel?) -> CGSize {
        sign == nil ? size : CGSize(width: size.width + signInset.width, height: size.height + signInset.height)
    }

    struct Palette: Sendable {
        let body: Color
        let ink: Color
        let face: Color
        let orb = Color(hex: 0xF7C455)
        let glow = Color(hex: 0xF5B833)

        init(onDark: Bool) {
            body = onDark ? Color(hex: 0x2F9587) : Color(hex: 0x17685F)
            ink = onDark ? Color(hex: 0x0C2D29) : Color(hex: 0x14332F)
            face = onDark ? Color(hex: 0xEAF7F3) : Color(hex: 0xDCEDE9)
        }
    }

    private struct Recipe {
        var eyes: Eyes
        var mouth: Path
        var arms: [Path]
        var accessory: Accessory = .none
        var brow = false
        var dim = false
    }

    private enum Eyes { case open, wide, look, arc, shut }
    private enum Accessory { case none, hand, magnifier }

    // Path diambil dari SVG maskot prototipe web (viewBox 156 × 180).
    private static let body = SVGPath.parse("M78 10C112 10 132 40 132 82c0 22-2 40-7 54c-8-2-14 2-15 9c-7-3-14 0-16 6c-4 4-9 7-16 7C46 158 24 132 24 90C24 44 44 10 78 10Z")
    private static let armDownL = SVGPath.parse("M42 98C24 106 11 126 15 145c3 11 17 11 21-1c4-13 8-31 10-41Z")
    private static let armDownR = SVGPath.parse("M114 98c18 8 31 28 27 47c-3 11-17 11-21-1c-4-13-8-31-10-41Z")
    private static let armUpR = SVGPath.parse("M118 94c19-10 34-33 30-50c-3-13-17-12-21 1c-4 15-12 37-14 45Z")
    private static let smile = SVGPath.parse("M69 71q9 9 18 0")
    private static let grin = SVGPath.parse("M66 69q12 15 24 0")
    private static let flat = SVGPath.parse("M70 74h16")
    private static let small = Path(ellipseIn: CGRect(x: 74, y: 69, width: 8, height: 8))
    private static let arcEyes = SVGPath.parse("M60 60q6-8 12 0M84 60q6-8 12 0")
    private static let shutEyes = SVGPath.parse("M60.5 58h11M84.5 58h11")
    private static let brow = SVGPath.parse("M57 39l13 6M99 39l-13 6")

    private static func leg(x: CGFloat) -> Path {
        UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10.5, bottomTrailing: 10.5))
            .path(in: CGRect(x: x, y: 148, width: 21, height: 30.5))
    }

    private static func recipe(for pose: MascotPose) -> Recipe {
        switch pose {
        case .wave: Recipe(eyes: .open, mouth: smile, arms: [armDownL, armUpR])
        case .calm: Recipe(eyes: .open, mouth: smile, arms: [armDownL, armDownR])
        case .stop: Recipe(eyes: .wide, mouth: flat, arms: [armDownL, armUpR], accessory: .hand, brow: true)
        case .check: Recipe(eyes: .look, mouth: small, arms: [armDownL, armUpR], accessory: .magnifier)
        case .happy: Recipe(eyes: .arc, mouth: grin, arms: [armDownL, armUpR])
        case .rest: Recipe(eyes: .shut, mouth: flat, arms: [armDownL, armDownR], dim: true)
        }
    }

    static func draw(pose: MascotPose, sign: RiskLevel? = nil, palette: Palette, time: TimeInterval?, in ctx: inout GraphicsContext, size: CGSize) {
        let art = box(sign: sign)
        let scale = min(size.width / art.width, size.height / art.height)
        ctx.translateBy(
            x: (size.width - art.width * scale) / 2,
            y: (size.height - art.height * scale) / 2
        )
        ctx.scaleBy(x: scale, y: scale)
        if sign != nil { ctx.translateBy(x: 0, y: signInset.height) }

        var recipe = recipe(for: pose)
        if sign != nil {
            recipe.arms = [armDownL, armUpR]
            recipe.accessory = .none
        }
        if recipe.dim { ctx.opacity = 0.78 }

        let outline = StrokeStyle(lineWidth: 5.4, lineCap: .round, lineJoin: .round)
        let feature = StrokeStyle(lineWidth: 4.3, lineCap: .round, lineJoin: .round)

        // Papan bergoyang pelan di tangan, bertumpu di genggaman.
        var sway: Double = 0
        if let time, sign != nil { sway = 3.5 * sin(time * 1.4) }
        var signCtx = ctx
        signCtx.translateBy(x: 137, y: 58)
        signCtx.rotate(by: .degrees(sway))
        signCtx.translateBy(x: -137, y: -58)
        if sign != nil {
            filled(Path(roundedRect: CGRect(x: 133.5, y: 8, width: 7, height: 52), cornerRadius: 3.5),
                   Color(hex: 0xC9D3D1), outline: palette.ink, style: StrokeStyle(lineWidth: 3.5), in: &signCtx)
        }

        for shape in [leg(x: 55), leg(x: 82)] + recipe.arms {
            filled(shape, palette.body, outline: palette.ink, style: outline, in: &ctx)
        }

        switch recipe.accessory {
        case .hand:
            var hand = Path()
            hand.addRoundedRect(in: CGRect(x: 110, y: 21, width: 35, height: 35), cornerSize: CGSize(width: 16, height: 16))
            hand.addRoundedRect(in: CGRect(x: 112, y: 7, width: 9, height: 21), cornerSize: CGSize(width: 4.5, height: 4.5))
            hand.addRoundedRect(in: CGRect(x: 123, y: 2, width: 9, height: 26), cornerSize: CGSize(width: 4.5, height: 4.5))
            hand.addRoundedRect(in: CGRect(x: 134, y: 7, width: 9, height: 21), cornerSize: CGSize(width: 4.5, height: 4.5))
            filled(hand, palette.body, outline: palette.ink, style: outline, in: &ctx)
        case .magnifier:
            var handle = Path()
            handle.move(to: CGPoint(x: 129, y: 45))
            handle.addLine(to: CGPoint(x: 118, y: 57))
            ctx.stroke(handle, with: .color(palette.ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            let lens = Path(ellipseIn: CGRect(x: 124, y: 15, width: 34, height: 34))
            filled(lens, palette.face, outline: palette.ink, style: StrokeStyle(lineWidth: 6.5), in: &ctx)
        case .none:
            break
        }

        filled(body, palette.body, outline: palette.ink, style: outline, in: &ctx)
        filled(Path(ellipseIn: CGRect(x: 48, y: 31, width: 60, height: 58)), palette.face, outline: palette.ink, style: outline, in: &ctx)

        // Kedip singkat tiap ±5 detik saat animasi aktif.
        var blink: CGFloat = 1
        if let time {
            let phase = time.truncatingRemainder(dividingBy: 5.4)
            if phase > 5.22 { blink = 0.12 }
        }

        switch recipe.eyes {
        case .open: eyes(centers: [CGPoint(x: 66, y: 57), CGPoint(x: 90, y: 57)], radius: 5.2, blink: blink, color: palette.ink, in: &ctx)
        case .wide: eyes(centers: [CGPoint(x: 66, y: 57), CGPoint(x: 90, y: 57)], radius: 7, blink: blink, color: palette.ink, in: &ctx)
        case .look: eyes(centers: [CGPoint(x: 69, y: 55), CGPoint(x: 93, y: 55)], radius: 5.2, blink: blink, color: palette.ink, in: &ctx)
        case .arc: ctx.stroke(arcEyes, with: .color(palette.ink), style: feature)
        case .shut: ctx.stroke(shutEyes, with: .color(palette.ink), style: feature)
        }

        if recipe.mouth == small {
            ctx.fill(small, with: .color(palette.ink))
        } else {
            ctx.stroke(recipe.mouth, with: .color(palette.ink), style: feature)
        }
        if recipe.brow {
            ctx.stroke(brow, with: .color(palette.ink), style: feature)
        }

        // Pendar titik dada berdenyut pelan.
        var pulse: CGFloat = 1
        if let time { pulse = 1 + 0.08 * CGFloat(sin(time * 1.9)) }
        let center = CGPoint(x: 78, y: 112)
        let orbOpacity: Double = recipe.dim ? 0.45 : 1
        for (radius, opacity) in [(19.0 * pulse, 0.22), (14.5 * pulse, 0.4)] {
            ctx.fill(circle(center, radius), with: .color(palette.glow.opacity(opacity * orbOpacity)))
        }
        ctx.fill(circle(center, 11), with: .color(palette.orb.opacity(orbOpacity)))

        if let sign { drawSign(sign, ink: palette.ink, in: &signCtx) }
    }

    /// Bentuk rambu mengikuti tingkat risiko, sama dengan ikon status di app.
    private static func drawSign(_ level: RiskLevel, ink: Color, in ctx: inout GraphicsContext) {
        let c = CGPoint(x: 137, y: -8)
        let edge = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
        switch level {
        case .safe:
            filled(circle(c, 25), Brand.safe, outline: ink, style: edge, in: &ctx)
            var check = Path()
            check.move(to: CGPoint(x: c.x - 11, y: c.y + 1))
            check.addLine(to: CGPoint(x: c.x - 3, y: c.y + 9))
            check.addLine(to: CGPoint(x: c.x + 12, y: c.y - 8))
            ctx.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        case .review:
            var tri = Path()
            tri.move(to: CGPoint(x: c.x, y: c.y - 29))
            tri.addLine(to: CGPoint(x: c.x + 29, y: c.y + 21))
            tri.addLine(to: CGPoint(x: c.x - 29, y: c.y + 21))
            tri.closeSubpath()
            filled(tri, Brand.signal, outline: ink, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round), in: &ctx)
            var bar = Path()
            bar.move(to: CGPoint(x: c.x, y: c.y - 12))
            bar.addLine(to: CGPoint(x: c.x, y: c.y + 4))
            ctx.stroke(bar, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + 13), 3.4), with: .color(ink))
        case .danger:
            func octagon(_ r: CGFloat) -> Path {
                var p = Path()
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4 + .pi / 8
                    let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
                return p
            }
            filled(octagon(28), Brand.danger, outline: ink, style: edge, in: &ctx)
            ctx.stroke(octagon(22), with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8))
            ctx.draw(Text("STOP").font(.system(size: 12.5, weight: .black, design: .rounded)).foregroundColor(.white), at: c)
        }
    }

    private static func filled(_ path: Path, _ fill: Color, outline: Color, style: StrokeStyle, in ctx: inout GraphicsContext) {
        ctx.fill(path, with: .color(fill))
        ctx.stroke(path, with: .color(outline), style: style)
    }

    private static func eyes(centers: [CGPoint], radius: CGFloat, blink: CGFloat, color: Color, in ctx: inout GraphicsContext) {
        for c in centers {
            let height = radius * 2 * blink
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - height / 2, width: radius * 2, height: height)), with: .color(color))
        }
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// Parser SVG path minimal (M, L, H, V, C, Q, Z, absolut dan relatif)
/// agar path maskot web bisa dipakai apa adanya.
enum SVGPath {
    private enum Token { case command(Character), number(CGFloat) }

    static func parse(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func number() -> CGFloat {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return 0 }
            index += 1
            return value
        }

        func point(relativeTo base: CGPoint) -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: base.x + x, y: base.y + y)
        }

        while index < tokens.count {
            if case .command(let c) = tokens[index] {
                command = c
                index += 1
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero

            switch command.uppercased() {
            case "M":
                current = point(relativeTo: base)
                subpathStart = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = point(relativeTo: base)
                path.addLine(to: current)
            case "H":
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                let c1 = point(relativeTo: base)
                let c2 = point(relativeTo: base)
                current = point(relativeTo: base)
                path.addCurve(to: current, control1: c1, control2: c2)
            case "Q":
                let c = point(relativeTo: base)
                current = point(relativeTo: base)
                path.addQuadCurve(to: current, control: c)
            case "Z":
                path.closeSubpath()
                current = subpathStart
                if index < tokens.count, case .number = tokens[index] { index += 1 }
            default:
                index += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""

        func flush() {
            if let value = Double(buffer) { tokens.append(.number(CGFloat(value))) }
            buffer = ""
        }

        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(.command(ch))
            } else if ch == "-" {
                flush()
                buffer = "-"
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "." && buffer.contains(".") {
                flush()
                buffer = "."
            } else {
                buffer.append(ch)
            }
        }
        flush()
        return tokens
    }
}
