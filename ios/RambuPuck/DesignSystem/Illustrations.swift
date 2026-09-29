import SwiftUI

// MARK: - Puck

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
