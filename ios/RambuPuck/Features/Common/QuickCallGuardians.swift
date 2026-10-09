import SwiftUI

/// Tombol cepat menelepon pengawas. Saat ragu di tengah telepon, cukup satu ketukan.
struct QuickCallGuardians: View {
    @Environment(AppState.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var callInfo: Person?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.guardians) { person in
                VStack(spacing: 10) {
                    Avatar(person: person, size: 52)
                    VStack(spacing: 1) {
                        Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                        Text(person.relation).font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .lineLimit(1)
                    if let url = person.telephoneURL {
                        Button {
                            openURL(url) { accepted in if !accepted { callInfo = person } }
                        } label: {
                            Label("Telepon", systemImage: "phone.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Brand.safe)
                        .accessibilityLabel("Telepon \(person.name)")
                    } else {
                        Text("Nomor belum ditambahkan").font(.caption).foregroundStyle(Brand.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                .shadow(color: Brand.ink.opacity(0.06), radius: 14, y: 6)
            }
        }
        .alert("Telepon \(callInfo?.name ?? "")", isPresented: .init(get: { callInfo != nil }, set: { if !$0 { callInfo = nil } })) {
            Button("Oke", role: .cancel) {}
        } message: {
            Text("Panggilan tidak dapat dibuka. Coba melalui aplikasi Telepon; simulator tidak mendukung panggilan.")
        }
    }
}
