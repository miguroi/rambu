import AppKit
import RambuPuckAgentCore
import SwiftUI

public struct PuckMenuView: View {
    @ObservedObject private var model: PuckControllerViewModel
    @Environment(\.openWindow) private var openWindow
    private let onQuit: @MainActor () -> Void

    public init(
        model: PuckControllerViewModel,
        onQuit: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.model = model
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusTitle).font(.headline)
                Spacer()
                Text("⌃⌥R").foregroundStyle(.secondary)
            }

            if shouldShowPairing {
                pairingForm
            } else {
                sessionControls
            }

            if let warning = model.latestWarning {
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.title).font(.headline)
                    Text(warning.recommendedAction).font(.caption)
                }
                .padding(8)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            HStack {
                Button("Lihat transkrip") { openWindow(id: "transcript") }
                    .disabled(model.transcriptLines.isEmpty)
                Spacer()
                Button("Keluar", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var pairingForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("URL server", text: $model.serverURLText)
                .textFieldStyle(.roundedBorder)
            TextField("Nama puck", text: $model.displayName)
                .textFieldStyle(.roundedBorder)
            TextField("Kode undangan 6 digit", text: $model.pairingCode)
                .textFieldStyle(.roundedBorder)
            Button(model.isPairing ? "Menghubungkan…" : "Hubungkan") {
                Task { await model.pair() }
            }
            .disabled(model.isPairing)
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        switch model.state {
        case .ready:
            Button("Mulai perlindungan") { Task { await model.start() } }
                .buttonStyle(.borderedProminent)
        case .listening, .warning:
            Button("Akhiri perlindungan") { Task { await model.end() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .error(_, let retrySession?) :
            Button("Coba kirim akhir sesi lagi") { Task { await model.retryEnd() } }
                .buttonStyle(.borderedProminent)
            Text("Sesi: \(retrySession)").font(.caption).foregroundStyle(.secondary)
        case .starting, .ending:
            ProgressView().controlSize(.small)
        case .disconnected, .error:
            EmptyView()
        }

        if case .error(let message, _) = model.state {
            Text(message).font(.caption).foregroundStyle(.red)
        }
        Button("Pasangkan ulang") { model.rePair() }
    }

    private var shouldShowPairing: Bool {
        if case .disconnected = model.state { return true }
        if case .error(_, nil) = model.state { return true }
        return false
    }

    private var statusTitle: String {
        switch model.state {
        case .disconnected: "Belum terhubung"
        case .ready: "Siap"
        case .starting: "Memulai…"
        case .listening: "Sedang mendengar"
        case .ending: "Mengakhiri…"
        case .warning(_, _, let warning): warning.title
        case .error: "Perlu perhatian"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .ready: .green
        case .starting, .ending: .orange
        case .listening: .blue
        case .warning(_, let severity, _): severity == .highRisk ? .red : .yellow
        case .disconnected, .error: .gray
        }
    }
}
