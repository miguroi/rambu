import SwiftUI

struct PuckScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        PuckIllustration(ledColor: model.puck.isCharging ? Brand.danger : nil)
                            .frame(maxWidth: 260)
                        Text(model.puck.name).font(Brand.display(.title2)).foregroundStyle(Brand.ink)
                        Label(model.puck.isConnected ? "Terhubung" : "Tidak terhubung",
                              systemImage: model.puck.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.puck.isConnected ? Brand.safeInk : Brand.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    LabeledContent {
                        Text("\(model.puck.battery)%").monospacedDigit()
                    } label: {
                        Label("Baterai", systemImage: model.puck.batterySymbol)
                    }
                    LabeledContent {
                        Text("Siap")
                    } label: {
                        Label("Mikrofon", systemImage: "mic.fill")
                    }
                    LabeledContent {
                        Text(model.puck.serial).monospaced()
                    } label: {
                        Label("Nomor seri", systemImage: "number")
                    }
                    LabeledContent {
                        Text(model.puck.firmware)
                    } label: {
                        Label("Firmware", systemImage: "cpu")
                    }
                }

                Section {
                    MicTestRow()
                } header: {
                    Text("Tes mikrofon")
                } footer: {
                    Text("Nyalakan loudspeaker lalu bicara di dekat HP. Puck perlu mendengar suara dari speaker dengan jelas.")
                }

                Section("Arti lampu") {
                    LightRow(color: Brand.danger, filled: true, title: "Merah menyala", detail: "Sedang mengisi daya")
                    LightRow(color: Brand.ink3, filled: false, title: "Mati", detail: "Baterai penuh, kabel boleh dicabut")
                }

                Section("Cara mengisi daya") {
                    StepRow(number: 1, text: "Pakai charger HP biasa dengan kabel USB-C.")
                    StepRow(number: 2, text: "Telungkupkan HP, lalu colok kabel ke cap putih puck.")
                    StepRow(number: 3, text: "Sekali isi sekitar 1 sampai 1,5 jam. Tidak perlu magnet.")
                }

                Section {
                    Button("Lepaskan puck dan ulangi demo", role: .destructive) { confirmUnpair = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.canvas)
            .navigationTitle("Rambu Puck")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoButton() } }
            .confirmationDialog("Lepaskan puck?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Lepaskan dan ulangi", role: .destructive) { model.resetDemo() }
            } message: {
                Text("Pengawas, riwayat, dan pengaturan demo akan kembali ke awal.")
            }
        }
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
        case .idle: "Belum dites"
        case .listening: "Mendengarkan…"
        case .done: "Suara terdengar jelas"
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

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.teal)
                .frame(width: 28, height: 28)
                .background(Brand.tealSoft, in: .circle)
                .frame(width: 32)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
