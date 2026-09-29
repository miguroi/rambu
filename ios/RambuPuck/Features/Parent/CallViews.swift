import SwiftUI

/// Simulasi layar telepon iPhone dengan banner Rambu di atasnya.
/// Di iPhone asli, layar telepon milik iOS; Rambu tampil lewat Live Activity dan Dynamic Island.
struct CallScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session {
            let alert = model.activeAlert
            ZStack(alignment: .top) {
                CallBackdrop(level: session.level)

                VStack(spacing: 0) {
                    HStack {
                        Label("Simulasi · \(session.scenario.channel.label)", systemImage: session.scenario.channel.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                        Spacer()
                        DemoButton()
                            .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 16)

                    RambuCallBanner(session: session, alert: alert, guardians: model.guardians)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    CallerHeader(session: session)
                        .padding(.top, 24)

                    Spacer(minLength: 16)

                    CallControls(emphasizeEnd: alert?.decision?.verdict == .scam) {
                        model.endCall()
                    }
                    .padding(.bottom, 20)
                }
            }
            .animation(.spring(duration: 0.5, bounce: 0.18), value: session.level)
            .animation(.spring(duration: 0.5, bounce: 0.18), value: alert?.decision)
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

private struct CallBackdrop: View {
    let level: RiskLevel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A3533), Color(hex: 0x121817)], startPoint: .top, endPoint: .bottom)
            // Aura tepi ikut tingkat risiko, dengan bentuk dan teks tetap jadi penanda utama.
            RadialGradient(
                colors: [level == .safe ? Brand.teal.opacity(0.35) : level.tint.opacity(0.55), .clear],
                center: .top, startRadius: 10, endRadius: 420
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: level)
        .accessibilityHidden(true)
    }
}

private struct CallerHeader: View {
    let session: CallSession

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 84, height: 84)
                .background(.white.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            Text(session.scenario.callerName)
                .font(.system(.title, design: .default, weight: .semibold))
                .foregroundStyle(.white)
            Text(session.scenario.callerDetail)
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Text(session.startedAt, style: .timer)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Banner Rambu di atas layar telepon. Membesar sesuai tingkat risiko
/// dan berubah jadi instruksi jelas begitu pengawas memutuskan.
struct RambuCallBanner: View {
    let session: CallSession
    let alert: FamilyAlert?
    let guardians: [Person]

    private var decision: GuardianDecision? { alert?.decision }

    private var tint: Color {
        if let decision { return decision.verdict == .scam ? Brand.danger : Brand.safe }
        return session.level == .safe ? Brand.teal : session.level.tint
    }

    private var pose: MascotPose {
        if let decision { return decision.verdict == .scam ? .stop : .calm }
        switch session.level {
        case .safe: return .calm
        case .review: return .check
        case .danger: return .stop
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(pose: pose, onDark: true)
                    .frame(width: 44, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAMBU")
                        .font(.caption2.weight(.heavy)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    statusLine
                }
                Spacer()
                if decision == nil && session.level == .safe {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .accessibilityLabel("Sedang mendengarkan")
                }
            }

            if let decision {
                decisionContent(decision)
            } else if session.level != .safe {
                warningContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.32)), in: .rect(cornerRadius: 30, style: .continuous))
        .sensoryFeedback(trigger: session.level) { _, new in
            switch new {
            case .danger: .error
            case .review: .warning
            case .safe: nil
            }
        }
        .sensoryFeedback(trigger: decision) { _, new in
            new?.verdict == .scam ? .error : (new == nil ? nil : .success)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let decision {
            Text("Jawaban dari \(decision.by.name)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        } else if session.level == .safe {
            Text("Mendengarkan · belum ada tanda penipuan")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        } else {
            HStack(spacing: 6) {
                LevelIcon(level: session.level, size: 16)
                Text(session.level.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
        }
    }

    private var warningContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.headline)
                .font(Brand.display(.title3))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.level.parentAdvice)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                AvatarStack(people: guardians, size: 24)
                Text("\(guardians.map(\.name).formatted(.list(type: .and).locale(Fmt.locale))) sudah diberi tahu")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func decisionContent(_ decision: GuardianDecision) -> some View {
        let scam = decision.verdict == .scam
        return VStack(alignment: .leading, spacing: 8) {
            Text(scam ? "Ini penipuan" : "Menurut \(decision.by.name), aman")
                .font(Brand.display(.title))
                .foregroundStyle(.white)
            Text(scam ? "Tutup teleponnya sekarang dengan tombol merah di bawah." : "Tetap jangan berikan kode atau transfer uang.")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
}

/// Tombol ala layar telepon iOS. Hanya "Akhiri" yang berfungsi di simulasi;
/// loudspeaker ditampilkan menyala karena puck hanya mendengar dari speaker.
private struct CallControls: View {
    let emphasizeEnd: Bool
    let onEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [(String, String, Bool)] = [
        ("Speaker", "speaker.wave.3.fill", true),
        ("FaceTime", "video.fill", false),
        ("Bisukan", "mic.slash.fill", false),
        ("Tambah", "person.badge.plus", false),
        ("Papan tombol", "circle.grid.3x3.fill", false),
        ("Lainnya", "ellipsis", false),
    ]

    var body: some View {
        VStack(spacing: 22) {
            GlassEffectContainer(spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                    ForEach(items, id: \.0) { item in
                        VStack(spacing: 6) {
                            Image(systemName: item.1)
                                .font(.title2)
                                .foregroundStyle(item.2 ? Color.black : .white)
                                .frame(width: 72, height: 72)
                                .background(item.2 ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .circle)
                                .glassEffect(item.2 ? .identity : .regular, in: .circle)
                            Text(item.0).font(.caption).foregroundStyle(.white.opacity(0.9))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.2 ? "\(item.0), menyala" : "\(item.0), tidak aktif di simulasi")
                    }
                }
                .padding(.horizontal, 36)
            }

            Button(action: onEnd) {
                Image(systemName: "phone.down.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(Color(hex: 0xEB4D3D), in: .circle)
            }
            .buttonStyle(.plain)
            .overlay {
                if emphasizeEnd && !reduceMotion {
                    Circle()
                        .stroke(Color(hex: 0xEB4D3D), lineWidth: 3)
                        .frame(width: 78, height: 78)
                        .phaseAnimator([false, true]) { view, grow in
                            view.scaleEffect(grow ? 1.45 : 1).opacity(grow ? 0 : 0.9)
                        } animation: { _ in .easeOut(duration: 1.1) }
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Akhiri panggilan")
        }
    }
}
