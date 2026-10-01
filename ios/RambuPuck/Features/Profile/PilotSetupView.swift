import SwiftUI

/// Setup intentionally lives behind Profile: the ordinary one-phone demo remains usable,
/// while a pilot can connect two physical phones to the same backend.
struct PilotSetupView: View {
    @Environment(AppState.self) private var model
    @Environment(PilotViewModel.self) private var pilot
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard

                    if model.pilotConnected {
                        connectedContent
                    } else {
                        setupContent
                    }

                    if let error = model.pilotError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Brand.dangerInk)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.dangerSoft, in: .rect(cornerRadius: 16))
                    }
                }
                .padding(24)
            }
            .background(Brand.canvas)
            .navigationTitle("Pilot dua HP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.pilotConnected ? "Terhubung ke server" : "Server pilot",
                  systemImage: model.pilotConnected ? "checkmark.icloud.fill" : "server.rack")
                .font(.headline)
                .foregroundStyle(model.pilotConnected ? Brand.safeInk : Brand.ink)
            TextField("http://alamat-mac:8000", text: Bindable(model).pilotServerURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.body.monospaced())
                .padding(12)
                .background(.white, in: .rect(cornerRadius: 12))
                .disabled(model.pilotConnected)
            Text("Simulator: 127.0.0.1. iPhone fisik: gunakan alamat Wi-Fi Mac dan jalankan backend dengan --host 0.0.0.0.")
                .font(.footnote)
                .foregroundStyle(Brand.ink3)
        }
        .card()
    }

    @ViewBuilder
    private var setupContent: some View {
        if model.persona.isParent {
            VStack(alignment: .leading, spacing: 12) {
                Text("Buat keluarga pilot").font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                Text("Server membuat kode undangan yang berlaku 10 menit.")
                    .foregroundStyle(Brand.ink2)
                Button { createFamily() } label: {
                    WideLabel(title: busy ? "Menghubungkan…" : "Buat kode", systemImage: "person.2.badge.plus")
                }
                .primaryAction()
                .disabled(busy)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gabung sebagai pengawas").font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                Text("Masukkan kode dari HP orang tua.").foregroundStyle(Brand.ink2)
                ZStack {
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .opacity(0.01)
                        .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                    DigitBoxes(digits: code, showsCursor: codeFocused)
                        .contentShape(.rect)
                        .onTapGesture { codeFocused = true }
                }
                Button { joinFamily() } label: {
                    WideLabel(title: busy ? "Menghubungkan…" : "Gabung", systemImage: "link")
                }
                .primaryAction()
                .disabled(busy || code.count != 6)
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.pilotRole == "parent" ? "Perangkat orang tua" : "Perangkat pengawas",
                  systemImage: model.pilotRole == "parent" ? "shield.fill" : "eye.fill")
                .font(.headline)
                .foregroundStyle(Brand.teal)

            if model.pilotRole == "parent", let code = model.pilotInviteCode {
                InviteActions(code: code)
                Button("Buat kode baru", systemImage: "arrow.clockwise") {
                    Task { await pilot.renewInvite() }
                }
                .font(.subheadline.weight(.semibold))
            }

            Button("Sinkronkan sekarang", systemImage: "arrow.triangle.2.circlepath") {
                Task { await pilot.refresh() }
            }
            .secondaryAction()

            Button("Putuskan dari pilot", role: .destructive) { pilot.disconnect() }
                .frame(maxWidth: .infinity)
        }
        .card()
    }

    private func createFamily() {
        busy = true
        Task {
            _ = await pilot.createFamily()
            busy = false
        }
    }

    private func joinFamily() {
        busy = true
        Task {
            _ = await pilot.joinFamily(code: code)
            busy = false
        }
    }
}
