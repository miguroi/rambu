import SwiftUI

// Latihan singkat di akhir onboarding: orang tua mengetuk push, pengawas memutuskan contoh peringatan.

// MARK: - Orang tua

/// Latihan singkat: ada telepon pura-pura, push Rambu turun, orang tua mengetuknya.
struct PracticeCallStep: View {
    @Environment(AppModel.self) private var model
    @State private var phase: Phase = .ringing

    enum Phase { case ringing, pushed, done }

    private var message: String {
        switch phase {
        case .ringing: "Ini telepon pura-pura. Tunggu sebentar."
        case .pushed: "Ketuk notifikasinya."
        case .done: "Begitu cara Rambu memberi tahu Anda."
        }
    }

    private let sample = Toast(id: "latihan", title: "Bahaya: terindikasi penipuan",
                               body: "Hati-hati. Jangan transfer atau sebut kode.", level: .danger, alertID: nil)

    var body: some View {
        StepScaffold(
            progress: (5, 5),
            title: phase == .done ? "Bagus!" : "Coba dulu",
            message: message
        ) {
            MiniPhone {
                VStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.14), in: .circle)
                    Text("Nomor tidak dikenal").font(.headline).foregroundStyle(.white)
                    Text("Telepon").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 110)
            } overlay: {
                if phase == .pushed {
                    Button { finish() } label: { PushBanner(toast: sample).frame(width: 370) }
                        .buttonStyle(.plain)
                        .scaleEffect(0.68, anchor: .top)
                        .frame(width: 252, alignment: .top)
                        .padding(.top, 42)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .overlay(alignment: .bottomTrailing) { TapHint().offset(x: -70, y: 6) }
                }
                if phase == .done {
                    MascotView(pose: .happy, sign: .safe)
                        .frame(height: 170)
                        .padding(.top, 60)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        } actions: {
            if phase == .done {
                Button { model.completeOnboarding(as: .ratna) } label: { WideLabel(title: "Selesai") }
                    .primaryAction()
            } else {
                Button { model.completeOnboarding(as: .ratna) } label: { WideLabel(title: "Lewati") }
                    .secondaryAction()
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: phase)
        .sensoryFeedback(.warning, trigger: phase) { _, new in new == .pushed }
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .done }
        .task {
            model.narrate("Ini telepon pura-pura. Tunggu sebentar.")
            try? await Task.sleep(for: .seconds(2))
            phase = .pushed
            model.narrate("Ada notifikasi dari Rambu. Ketuk notifikasinya.")
        }
    }

    private func finish() {
        phase = .done
        model.narrate("Bagus. Begitu cara Rambu memberi tahu Anda.")
    }
}

/// Jari yang mengetuk berulang, penanda "ketuk di sini".
struct TapHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 34))
            .foregroundStyle(.white, Brand.ink)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { view, pressed in
                view.scaleEffect(pressed ? 0.85 : 1).offset(y: pressed ? -6 : 0)
            } animation: { _ in .easeInOut(duration: 0.6) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Pengawas

/// Contoh peringatan untuk dicoba. Pengawas belajar membaca kalimat lalu memilih.
struct PracticeAlertStep: View {
    @Environment(AppModel.self) private var model
    @State private var answer: Verdict?

    private let line = TranscriptLine(id: 0, offset: 20, speaker: .caller,
                                      text: "Tolong bacakan kode OTP-nya ke saya ya, Bu. Biar transaksinya saya batalkan.",
                                      flagged: ["bacakan kode OTP-nya ke saya"], signals: [.secretCode])

    var body: some View {
        StepScaffold(progress: (3, 3), title: "Coba putuskan", message: "Contoh peringatan. Menurut Anda?") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: RiskLevel.danger.symbol)
                    Text("Bahaya")
                    Spacer()
                    Text("Contoh").font(.subheadline.weight(.semibold))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Brand.danger)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("\(model.parent.name) mungkin sedang ditipu")
                            .font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                        Spacer(minLength: 0)
                        MascotView(pose: .stop, sign: .danger).frame(width: 54)
                    }
                    EvidenceCard(line: line, level: .danger)
                }
                .padding(16)
            }
            .background(Brand.dangerSoft)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))

            if let answer {
                feedback(for: answer).transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        } actions: {
            if answer == .scam {
                Button { model.onboardingStep = .waiting } label: { WideLabel(title: "Lanjut") }
                    .primaryAction()
            } else {
                HStack(spacing: 10) {
                    Button { withAnimation(.smooth) { answer = .safe } } label: { WideLabel(title: "Aman", systemImage: "checkmark") }
                        .secondaryAction()
                    Button { withAnimation(.smooth) { answer = .scam } } label: { WideLabel(title: "Penipuan", systemImage: "hand.raised.fill") }
                        .primaryAction(Brand.danger)
                }
            }
        }
        .sensoryFeedback(trigger: answer) { _, new in new == .scam ? .success : .warning }
    }

    private func feedback(for answer: Verdict) -> some View {
        let right = answer == .scam
        return HStack(spacing: 14) {
            MascotView(pose: right ? .happy : .check, sign: right ? .safe : .review).frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(right ? "Tepat" : "Coba lagi").font(.headline).foregroundStyle(Brand.ink)
                Text(right ? "Orang tua langsung diminta menutup telepon." : "Meminta kode OTP selalu tanda penipuan.")
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(right ? Brand.safeSoft : Brand.signalSoft, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Bingkai HP

/// Bingkai HP kecil untuk latihan dan tutorial.
struct MiniPhone<Content: View, Overlay: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x3A4442), Color(hex: 0x151A19)], startPoint: .top, endPoint: .bottom)
            content
            overlay
            Capsule().fill(.black).frame(width: 84, height: 24).padding(.top, 10)
        }
        .frame(width: 270, height: 420)
        .clipShape(.rect(cornerRadius: 44, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(Brand.ink, lineWidth: 6) }
        .frame(maxWidth: .infinity)
    }
}
