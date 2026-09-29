import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.onboardingStep {
                case .welcome: WelcomeStep()
                case .parentProfile: ParentProfileStep()
                case .guardianProfile: GuardianProfileStep()
                case .pairPuck: PairPuckStep()
                case .consent: ConsentStep()
                case .invite: InviteGuardiansStep()
                case .enterCode: EnterCodeStep()
                case .waiting: GuardianWaitingStep()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .background(Brand.canvas.ignoresSafeArea())
            .toolbar {
                if model.onboardingStep != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Kembali", systemImage: "chevron.left") { goBack() }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.onboardingStep)
    }

    private func goBack() {
        switch model.onboardingStep {
        case .parentProfile, .enterCode: model.onboardingStep = .welcome
        case .pairPuck: model.onboardingStep = .parentProfile
        case .consent: model.onboardingStep = .pairPuck
        case .invite: model.onboardingStep = .consent
        case .guardianProfile: model.onboardingStep = .enterCode
        case .waiting: model.onboardingStep = .guardianProfile
        case .welcome: break
        }
    }
}

/// Kerangka langkah: judul, isi, dan tombol di bawah.
private struct StepScaffold<Content: View, Actions: View>: View {
    var step: String?
    let title: String
    let message: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    if let step {
                        Text(step).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.teal)
                    }
                    Text(title).font(Brand.display(.largeTitle)).foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message).font(.body).foregroundStyle(Brand.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Selamat datang

private struct WelcomeStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("Wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    .accessibilityLabel("Rambu")
                    .padding(.top, 12)

                MascotView(pose: .wave)
                    .frame(height: typeSize.isAccessibilitySize ? 150 : 220)
                    .padding(.vertical, 4)

                VStack(spacing: 10) {
                    Text("Kenali tanda, hindari tipu daya.")
                        .font(Brand.display(.title))
                        .foregroundStyle(Brand.ink)
                        .multilineTextAlignment(.center)
                    Text("Rambu Puck mendengarkan telepon yang memakai loudspeaker, lalu memberi tahu keluarga saat ada tanda penipuan.")
                        .font(.body)
                        .foregroundStyle(Brand.ink2)
                        .multilineTextAlignment(.center)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                Button { model.onboardingStep = .parentProfile } label: {
                    WideLabel(title: "Saya ingin dilindungi", systemImage: "shield.lefthalf.filled")
                }
                .primaryAction()
                Button { model.onboardingStep = .enterCode } label: {
                    WideLabel(title: "Saya menjaga keluarga", systemImage: "person.2.fill")
                }
                .secondaryAction()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Isian nama

/// Kolom nama besar dan jelas. Sudah terisi data contoh, tetap bisa diubah.
private struct NameField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2)
            TextField(prompt, text: $text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.name)
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(minHeight: 58)
                .background(.white, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.hairline)
                }
        }
    }
}

private struct DemoPrefillNote: View {
    var body: some View {
        Label("Sudah diisi contoh untuk demo. Boleh diganti.", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(Brand.ink3)
    }
}

// MARK: - Orang tua: nama

private struct ParentProfileStep: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        StepScaffold(
            step: "Langkah 1 dari 4",
            title: "Siapa nama Anda?",
            message: "Nama ini yang dilihat keluarga saat Rambu memberi tahu mereka."
        ) {
            NameField(title: "Nama panggilan", text: $name, prompt: "Contoh: Ibu Ratna")
            DemoPrefillNote()
        } actions: {
            Button {
                model.renameParent(name)
                model.onboardingStep = .pairPuck
            } label: { WideLabel(title: "Lanjut") }
                .primaryAction()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { if name.isEmpty { name = model.parent.name } }
    }
}

// MARK: - Pengawas: nama dan hubungan

private struct GuardianProfileStep: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var relation = "Anak"

    private let relations = ["Anak", "Cucu", "Saudara"]

    var body: some View {
        StepScaffold(
            step: "Untuk pengawas · langkah 2 dari 2",
            title: "Perkenalkan diri Anda",
            message: "\(model.parent.name) akan melihat nama ini sebelum mengizinkan Anda."
        ) {
            NameField(title: "Nama Anda", text: $name, prompt: "Contoh: Sinta")

            VStack(alignment: .leading, spacing: 8) {
                Text("Hubungan dengan \(model.parent.name)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2)
                HStack(spacing: 8) {
                    ForEach(relations, id: \.self) { option in
                        Button { relation = option } label: {
                            Text(option)
                                .font(.headline)
                                .foregroundStyle(relation == option ? .white : Brand.ink)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(relation == option ? Brand.teal : .white, in: .capsule)
                                .overlay { Capsule().strokeBorder(relation == option ? .clear : Brand.hairline) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(relation == option ? .isSelected : [])
                    }
                }
            }
            DemoPrefillNote()
        } actions: {
            Button {
                model.renameGuardian(.sinta, name: name, relation: relation)
                model.onboardingStep = .waiting
            } label: { WideLabel(title: "Kirim permintaan") }
                .primaryAction()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            if name.isEmpty {
                let me = model.person(for: .sinta)
                name = me.name
                relation = me.relation
            }
        }
    }
}

// MARK: - Orang tua: pasang puck

private struct PairPuckStep: View {
    @Environment(AppModel.self) private var model
    @State private var phase: Phase = .idle
    @State private var found: PuckState?

    enum Phase { case idle, searching, found }

    var body: some View {
        StepScaffold(
            step: "Langkah 2 dari 4",
            title: "Pasang Rambu Puck",
            message: "Tempelkan puck di punggung HP, lalu tekan tombol di sisinya sampai lampunya berkedip."
        ) {
            VStack(spacing: 16) {
                ZStack {
                    if phase == .searching { SearchRings() }
                    PuckIllustration(ledColor: phase == .idle ? nil : Brand.tealBright)
                        .frame(maxWidth: 240)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)

                if let found, phase == .found {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.safe)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(found.name) ditemukan").font(.headline).foregroundStyle(Brand.ink)
                            Text("\(found.serial) · baterai \(found.battery)%").font(.subheadline).foregroundStyle(Brand.ink2)
                        }
                    }
                    .card()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        } actions: {
            switch phase {
            case .idle:
                Button { search() } label: { WideLabel(title: "Cari puck", systemImage: "dot.radiowaves.left.and.right") }
                    .primaryAction()
            case .searching:
                Button {} label: {
                    HStack(spacing: 10) { ProgressView(); Text("Mencari puck di dekat Anda…") }
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .secondaryAction()
                .disabled(true)
            case .found:
                Button { model.onboardingStep = .consent } label: { WideLabel(title: "Hubungkan") }
                    .primaryAction()
            }
        }
        .animation(.smooth, value: phase)
    }

    private func search() {
        phase = .searching
        Task {
            let state = await SimulatedPuckLink().discover()
            found = state
            phase = .found
        }
    }
}

private struct SearchRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Brand.teal.opacity(0.25), lineWidth: 2)
                    .scaleEffect(expand ? 1.35 : 0.6)
                    .opacity(expand ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: expand)
            }
        }
        .frame(width: 220, height: 220)
        .onAppear { expand = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Orang tua: persetujuan

private struct ConsentStep: View {
    @Environment(AppModel.self) private var model
    @State private var agreed = false

    private let points: [(String, String)] = [
        ("speaker.wave.3.fill", "Puck hanya mendengar suara dari loudspeaker. Telepon yang ditempel di telinga tidak terdengar."),
        ("text.quote", "Kalau ada tanda penipuan, pengawas Anda hanya menerima kalimat yang mencurigakan, bukan seluruh percakapan."),
        ("hand.raised.fill", "Anda tetap yang memutuskan. Rambu tidak bisa dan tidak akan menutup telepon Anda."),
    ]

    var body: some View {
        StepScaffold(
            step: "Langkah 3 dari 4",
            title: "Sebelum Rambu mendengarkan",
            message: "Tiga hal yang berlaku sejak awal."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(points.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: points[index].0)
                            .font(.title3)
                            .foregroundStyle(Brand.teal)
                            .frame(width: 44, height: 44)
                            .background(Brand.tealSoft, in: .rect(cornerRadius: 13, style: .continuous))
                        Text(points[index].1)
                            .font(.body)
                            .foregroundStyle(Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    if index < points.count - 1 { Divider() }
                }
            }
            .card()

            Toggle(isOn: $agreed) {
                Text("Saya mengerti dan setuju").font(.body.weight(.semibold)).foregroundStyle(Brand.ink)
            }
            .toggleStyle(.switch)
            .tint(Brand.teal)
            .card()
        } actions: {
            Button { model.onboardingStep = .invite } label: { WideLabel(title: "Setuju dan lanjut") }
                .primaryAction()
                .disabled(!agreed)
        }
    }
}

// MARK: - Orang tua: undang pengawas

private struct InviteGuardiansStep: View {
    @Environment(AppModel.self) private var model
    @State private var requests: [Person] = []
    @State private var approved: Set<String> = []

    var body: some View {
        StepScaffold(
            step: "Langkah 4 dari 4",
            title: "Hubungkan pengawas",
            message: "Minta anak Anda membuka aplikasi Rambu dan memasukkan kode ini. Anda bisa punya lebih dari satu pengawas."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DigitBoxes(digits: "482913")
                Label("Berlaku 10 menit", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(Brand.ink3)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Permintaan masuk")
                if requests.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Menunggu pengawas memasukkan kode…").font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(requests) { person in
                            requestRow(person)
                            if person != requests.last { Divider().padding(.leading, 58) }
                        }
                    }
                    .card(padding: 14)
                }
            }
        } actions: {
            Button { model.completeOnboarding(as: .ratna) } label: {
                WideLabel(title: approved.isEmpty ? "Izinkan minimal satu pengawas" : "Selesai")
            }
            .primaryAction()
            .disabled(approved.isEmpty)
        }
        .task { await simulateRequests() }
    }

    private func requestRow(_ person: Person) -> some View {
        HStack(spacing: 12) {
            Avatar(person: person, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                Text(approved.contains(person.id) ? "\(person.relation) · terhubung" : "\(person.relation) · ingin menjaga Anda")
                    .font(.subheadline)
                    .foregroundStyle(approved.contains(person.id) ? Brand.safeInk : Brand.ink2)
            }
            Spacer()
            if approved.contains(person.id) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.safe)
                    .accessibilityLabel("Terhubung")
            } else {
                Button("Izinkan") {
                    withAnimation(.smooth) { _ = approved.insert(person.id) }
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.teal)
            }
        }
        .padding(.vertical, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func simulateRequests() async {
        for person in model.guardians where !requests.contains(person) {
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.smooth) { requests.append(person) }
        }
    }
}

// MARK: - Pengawas: masukkan kode

private struct EnterCodeStep: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        StepScaffold(
            step: "Untuk pengawas · langkah 1 dari 2",
            title: "Masukkan kode dari orang tua Anda",
            message: "Kode 6 angka ada di aplikasi Rambu milik orang tua Anda."
        ) {
            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .accessibilityLabel("Kode 6 angka")
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }
                DigitBoxes(digits: code, showsCursor: focused)
                    .contentShape(.rect)
                    .onTapGesture { focused = true }
            }
            Text("Kode contoh untuk demo: 482 913")
                .font(.subheadline).foregroundStyle(Brand.ink3)
        } actions: {
            Button { model.onboardingStep = .guardianProfile } label: { WideLabel(title: "Lanjut") }
                .primaryAction()
                .disabled(code.count < 6)
        }
        .onAppear { focused = true }
    }
}

private struct GuardianWaitingStep: View {
    @Environment(AppModel.self) private var model
    @State private var connected = false

    var body: some View {
        let me = model.person(for: .sinta)
        let partner = model.person(for: .richard)
        StepScaffold(
            step: "Untuk pengawas",
            title: connected ? "Terhubung dengan \(model.parent.name)" : "Menunggu izin",
            message: connected
                ? "Anda menjaga \(model.parent.name) bersama \(partner.name). Jawaban pertama yang masuk yang berlaku, jadi cukup salah satu dari kalian."
                : "\(model.parent.name) perlu mengizinkan permintaan Anda di HP-nya."
        ) {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Avatar(person: me, size: 64)
                    Image(systemName: connected ? "link" : "ellipsis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(connected ? Brand.safe : Brand.ink3)
                        .symbolEffect(.pulse, isActive: !connected)
                    Avatar(person: model.parent, size: 64)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                MascotView(pose: connected ? .happy : .check)
                    .frame(height: 150)
            }
        } actions: {
            Button { model.completeOnboarding(as: .sinta) } label: { WideLabel(title: "Mulai menjaga") }
                .primaryAction()
                .disabled(!connected)
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { connected = true }
        }
    }
}
