import SwiftUI

/// Profil: cukup nama dan hubungan. Rambu bukan media sosial, jadi tidak ada foto.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var relation = "Anak"
    @State private var showInvite = false
    @State private var showJoin = false
    @State private var showTutorial = false
    @State private var confirmClear = false
    @State private var confirmReset = false

    private let relations = ["Anak", "Cucu", "Saudara"]

    var body: some View {
        let me = model.currentPerson
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Avatar(person: me, size: 72)
                        Text(me.name).font(Brand.display(.title2)).foregroundStyle(Brand.ink)
                        Text(model.persona.isParent ? "Dilindungi Rambu" : "Pengawas")
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Nama") {
                    TextField("Nama panggilan", text: $name)
                        .font(.body.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    if !model.persona.isParent {
                        Picker("Hubungan", selection: $relation) {
                            ForEach(relations, id: \.self) { Text($0) }
                        }
                        .onChange(of: relation) { saveName() }
                    }
                }

                if model.persona.isParent {
                    guardiansSection
                } else {
                    parentsSection
                }

                Section("Peringatan") {
                    HStack {
                        Label("Notifikasi", systemImage: "bell.badge.fill")
                        Spacer()
                        if model.notificationsAuthorized {
                            Text("Aktif").foregroundStyle(Brand.safeInk)
                        } else {
                            Button("Nyalakan") { enableNotifications() }
                                .buttonStyle(.glassProminent).tint(Brand.teal)
                        }
                    }
                    Toggle(isOn: Binding(get: { model.narrationEnabled }, set: { model.setNarration($0) })) {
                        Label("Bacakan peringatan", systemImage: "speaker.wave.2.fill")
                    }
                    .tint(Brand.teal)
                }

                Section("Bantuan") {
                    Button { showTutorial = true } label: {
                        Label("Ulangi tutorial", systemImage: "play.circle.fill")
                    }
                    if model.persona.isParent {
                        Button(role: .destructive) { confirmClear = true } label: {
                            Label("Hapus riwayat", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button { openDemo() } label: {
                        Label("Mode demo", systemImage: "person.2.badge.gearshape.fill")
                    }
                    Button("Keluar dan mulai ulang", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Semua data tersimpan di HP ini saja.")
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai", systemImage: "checkmark") {
                        saveName()
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = me.name
                relation = me.relation
            }
            .sheet(isPresented: $showInvite) { InviteSheet() }
            .sheet(isPresented: $showJoin) { JoinParentSheet() }
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialCarousel(isParent: model.persona.isParent) { showTutorial = false }
            }
            .confirmationDialog("Hapus semua riwayat?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Hapus", role: .destructive) { model.clearHistory() }
            }
            .confirmationDialog("Keluar dan mulai ulang?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Keluar", role: .destructive) { model.resetDemo() }
            } message: {
                Text("Nama, pengawas, dan riwayat di HP ini dihapus.")
            }
        }
    }

    private var guardiansSection: some View {
        Section {
            ForEach(model.guardians) { person in
                PersonRow(person: person)
                    .swipeActions {
                        if model.guardians.count > 1 {
                            Button("Hapus", role: .destructive) { model.removeGuardian(person) }
                        }
                    }
            }
            Button { showInvite = true } label: {
                Label("Undang pengawas", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Pengawas")
        } footer: {
            Text("Geser ke kiri untuk menghapus. Minimal satu pengawas.")
        }
    }

    private var parentsSection: some View {
        Section("Yang Anda jaga") {
            ForEach(model.protectedParents) { person in
                PersonRow(person: person)
                    .swipeActions {
                        if model.extraParents.contains(person) {
                            Button("Berhenti", role: .destructive) { model.removeProtectedParent(person) }
                        }
                    }
            }
            Button { showJoin = true } label: {
                Label("Jaga orang tua lain", systemImage: "plus.circle.fill")
            }
        }
    }

    private func saveName() {
        if model.persona.isParent {
            model.renameParent(name)
        } else {
            model.renameGuardian(model.persona, name: name, relation: relation)
        }
    }

    private func enableNotifications() {
        Task {
            await model.requestNotifications()
            if !model.notificationsAuthorized, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
            }
        }
    }

    /// Profil dan Mode demo sama-sama sheet di RootView, jadi Profil ditutup dulu
    /// sebelum Mode demo dibuka.
    private func openDemo() {
        saveName()
        model.showProfile = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            model.showDemoSheet = true
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            Avatar(person: person, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                Text(person.relation).font(.subheadline).foregroundStyle(Brand.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Undangan

/// Kode undangan plus cara mengirimnya. Tautan https bisa diketuk langsung di WhatsApp.
struct InviteActions: View {
    let code: String
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        let link = InviteLink.url(code: code)
        VStack(alignment: .leading, spacing: 12) {
            DigitBoxes(digits: code)
            Label("Berlaku 10 menit", systemImage: "clock")
                .font(.subheadline).foregroundStyle(Brand.ink3)

            Link(destination: InviteLink.whatsAppURL(code: code, parentName: model.parent.name)) {
                WideLabel(title: "Kirim lewat WhatsApp", systemImage: "paperplane.fill")
            }
            .primaryAction(Color(hex: 0x1FA855))

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = InviteLink.message(code: code, parentName: model.parent.name)
                    withAnimation(.smooth) { copied = true }
                } label: {
                    WideLabel(title: copied ? "Tersalin" : "Salin tautan", systemImage: copied ? "checkmark" : "link")
                }
                .secondaryAction()
                ShareLink(item: link, message: Text(InviteLink.message(code: code, parentName: model.parent.name))) {
                    WideLabel(title: "Lainnya", systemImage: "square.and.arrow.up")
                }
                .secondaryAction()
            }
        }
    }
}

private struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Kirim tautan ini ke anak Anda. Mereka tinggal mengetuknya.")
                        .font(.body).foregroundStyle(Brand.ink2)
                    InviteActions(code: "482913")
                }
                .padding(24)
            }
            .background(Brand.canvas)
            .navigationTitle("Undang pengawas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Pengawas menambah orang tua lain lewat kode 6 angka.
private struct JoinParentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var added: Person?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let added {
                    VStack(spacing: 12) {
                        MascotView(pose: .happy, sign: .safe).frame(height: 130)
                        Text("Sekarang Anda menjaga \(added.name)")
                            .font(Brand.display(.title3)).foregroundStyle(Brand.ink)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    Button { dismiss() } label: { WideLabel(title: "Selesai") }.primaryAction()
                } else {
                    Text("Masukkan kode dari aplikasi Rambu orang tua.")
                        .font(.body).foregroundStyle(Brand.ink2)
                    ZStack {
                        TextField("", text: $code)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .opacity(0.01)
                            .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                        DigitBoxes(digits: code, showsCursor: focused)
                            .contentShape(.rect)
                            .onTapGesture { focused = true }
                    }
                    Button("Isi kode demo 715 204", systemImage: "wand.and.stars") { code = "715204" }
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.smooth) { added = model.addProtectedParent(code: code) }
                    } label: { WideLabel(title: "Gabung") }
                        .primaryAction()
                        .disabled(code.count < 6)
                }
            }
            .padding(24)
            .background(Brand.canvas)
            .navigationTitle("Jaga orang tua lain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
