import SwiftUI

/// Simulasi layar telepon bawaan iPhone atau WhatsApp. Layar ini bukan milik Rambu,
/// jadi Rambu hanya hadir lewat push dari atas dan Live Activity, seperti di HP asli.
struct CallScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session {
            ZStack(alignment: .top) {
                CallBackdrop(channel: session.scenario.channel)

                VStack(spacing: 0) {
                    HStack {
                        Label("Simulasi", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                        Spacer()
                        DemoButton()
                            .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 16)

                    CallerHeader(session: session)
                        .padding(.top, 72)

                    Spacer(minLength: 16)

                    CallControls { model.endCall() }
                        .padding(.bottom, 20)
                }

                ToastOverlay()
                    .padding(.top, 2)
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

private struct CallBackdrop: View {
    let channel: CallChannel

    var body: some View {
        LinearGradient(
            colors: channel == .whatsapp
                ? [Color(hex: 0x1C2B27), Color(hex: 0x0B1412)]
                : [Color(hex: 0x3A4442), Color(hex: 0x151A19)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
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
            HStack(spacing: 6) {
                if session.scenario.channel == .whatsapp {
                    Image(systemName: "lock.fill").font(.caption)
                    Text("WhatsApp")
                    Text("·")
                }
                Text(session.startedAt, style: .timer).monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tombol ala layar telepon iOS. Hanya "Akhiri" yang berfungsi di simulasi;
/// loudspeaker ditampilkan menyala karena puck hanya mendengar dari speaker.
private struct CallControls: View {
    let onEnd: () -> Void

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
            .accessibilityLabel("Akhiri panggilan")
        }
    }
}
