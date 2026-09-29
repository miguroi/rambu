import SwiftUI

struct PuckScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        PuckIllustration(ledColor: model.puck.isCharging ? Brand.danger : nil)
                            .frame(maxWidth: 240)
                        HStack(spacing: 8) {
                            StatusPill(systemImage: model.puck.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill",
                                       text: model.puck.isConnected ? "Terhubung" : "Terputus",
                                       tint: model.puck.isConnected ? Brand.safeInk : Brand.ink3,
                                       background: model.puck.isConnected ? Brand.safeSoft : Brand.hairline)
                            StatusPill(systemImage: model.puck.batterySymbol, text: "\(model.puck.battery)%",
                                       tint: Brand.ink, background: .white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                Section {
                    MicTestRow()
                } footer: {
                    Text("Nyalakan loudspeaker, lalu bicara.")
                }

                Section("Arti lampu") {
                    LightRow(color: Brand.danger, filled: true, title: "Menyala merah", detail: "Mengisi daya")
                    LightRow(color: Brand.ink3, filled: false, title: "Mati", detail: "Penuh, cabut kabel")
                }

                Section("Isi daya") {
                    ChargeSteps()
                        .listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
                }

                Section {
                    Button("Lepaskan puck", role: .destructive) { confirmUnpair = true }
                } footer: {
                    Text("\(model.puck.serial), firmware \(model.puck.firmware)").monospacedDigit()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.canvas)
            .navigationTitle("Rambu Puck")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
            .confirmationDialog("Lepaskan puck?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Lepaskan", role: .destructive) { model.resetDemo() }
            } message: {
                Text("Demo kembali ke awal.")
            }
        }
    }
}

private struct StatusPill: View {
    let systemImage: String
    let text: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background, in: .capsule)
    }
}

/// Tiga langkah isi daya sebagai ikon berjajar.
private struct ChargeSteps: View {
    private let steps: [(symbol: String, label: String)] = [
        ("cable.connector", "Kabel USB-C"),
        ("iphone.gen3", "Telungkupkan HP"),
        ("clock.fill", "±1,5 jam"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(steps, id: \.label) { step in
                VStack(spacing: 8) {
                    Image(systemName: step.symbol)
                        .font(.title2)
                        .foregroundStyle(Brand.teal)
                        .frame(width: 52, height: 52)
                        .background(Brand.tealSoft, in: .circle)
                    Text(step.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MicTestRow: View {
    @State private var phase: Phase = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase { case idle, listening, done }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                switch phase {
                case .idle:
                    Image(systemName: "waveform").foregroundStyle(Brand.ink3)
                case .listening:
                    Image(systemName: "waveform").foregroundStyle(Brand.teal)
                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.safe)
                }
            }
            .font(.title2)
            .frame(width: 32)

            Text(label).font(.body).foregroundStyle(Brand.ink)
            Spacer()
            if phase != .listening {
                Button(phase == .done ? "Ulangi" : "Tes") { run() }
                    .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch phase {
        case .idle: "Tes mikrofon"
        case .listening: "Mendengarkan…"
        case .done: "Terdengar jelas"
        }
    }

    private func run() {
        phase = .listening
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            phase = .done
        }
    }
}

private struct LightRow: View {
    let color: Color
    let filled: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(filled ? color : .clear)
                .overlay(Circle().stroke(color, lineWidth: filled ? 0 : 2))
                .frame(width: 16, height: 16)
                .shadow(color: filled ? color.opacity(0.6) : .clear, radius: 6)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(Brand.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
