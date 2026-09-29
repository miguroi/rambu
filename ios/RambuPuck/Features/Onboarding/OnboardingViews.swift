import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.onboardingStep {
                case .welcome: WelcomeStep()
                case .tutorial: TutorialCarousel(isParent: true) { model.onboardingStep = .parentProfile }
                case .parentProfile: ParentProfileStep()
                case .guardianProfile: GuardianProfileStep()
                case .pairPuck: PairPuckStep()
                case .consent: ConsentStep()
                case .invite: InviteGuardiansStep()
                case .enterCode: EnterCodeStep()
                case .practiceCall: PracticeCallStep()
                case .practiceAlert: PracticeAlertStep()
                case .waiting: GuardianWaitingStep()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .background(Brand.canvas.ignoresSafeArea())
            .toolbar {
                if model.onboardingStep != .welcome && model.onboardingStep != .tutorial {
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
        case .tutorial, .enterCode: model.onboardingStep = .welcome
        case .parentProfile: model.onboardingStep = .tutorial
        case .pairPuck: model.onboardingStep = .parentProfile
        case .consent: model.onboardingStep = .pairPuck
        case .invite: model.onboardingStep = .consent
        case .practiceCall: model.onboardingStep = .invite
        case .guardianProfile: model.onboardingStep = .enterCode
        case .practiceAlert: model.onboardingStep = .guardianProfile
        case .waiting: model.onboardingStep = .practiceAlert
        case .welcome: break
        }
    }
}

/// Kerangka langkah: progres, judul, satu kalimat pendek, isi, lalu tombol di bawah.
private struct StepScaffold<Content: View, Actions: View>: View {
    var progress: (Int, Int)?
    let title: String
    var message: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    if let progress {
                        StepProgress(current: progress.0, total: progress.1)
                            .padding(.bottom, 4)
                    }
                    Text(title).font(Brand.display(.largeTitle)).foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message).font(.body).foregroundStyle(Brand.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPush = false

    private let sample = Toast(id: "sambutan", title: "Bahaya: terindikasi penipuan",
                               body: "Sudah dikirim ke Sinta dan Richard.", level: .danger, alertID: nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Foto asli: ibu dan anak di Bandung (Tuti Isnawati, Pexels).
                Image("PhotoWelcome")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 470)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Brand.canvas.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 130)
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, Brand.canvas], startPoint: .top, endPoint: .bottom)
                            .frame(height: 170)
                    }
                    .overlay(alignment: .topLeading) {
                        Image("Wordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 26)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.9), in: .capsule)
                            .padding(.leading, 20)
                            .padding(.top, 62)
                            .accessibilityLabel("Rambu")
                    }
                    .overlay(alignment: .bottom) {
                        if showPush {
                            PushBanner(toast: sample)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 44)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .accessibilityLabel("Seorang ibu dan anaknya duduk di teras rumah")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Kenali tanda, hindari tipu daya.")
                        .font(Brand.display(.largeTitle))
                        .foregroundStyle(Brand.ink)
                    Text("Puck di punggung HP ikut mendengar telepon. Ada tanda penipuan, keluarga langsung tahu.")
                        .font(.body)
                        .foregroundStyle(Brand.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, -18)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                Button { model.onboardingStep = .tutorial } label: {
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
        .task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.3)) { showPush = true }
        }
        .sensoryFeedback(.warning, trigger: showPush) { _, new in new }
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
        Label("Contoh untuk demo, boleh diganti", systemImage: "pencil")
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
            progress: (1, 5),
            title: "Siapa nama Anda?",
            message: "Nama ini muncul di HP keluarga."
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
            progress: (2, 3),
            title: "Siapa Anda?",
            message: "\(model.parent.name) melihat nama ini sebelum mengizinkan."
        ) {
            NameField(title: "Nama Anda", text: $name, prompt: "Contoh: Sinta")

            VStack(alignment: .leading, spacing: 8) {
                Text("Hubungan").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2)
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
                model.onboardingStep = .practiceAlert
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
            progress: (2, 5),
            title: "Pasang puck",
            message: "Tempel di punggung HP, lalu tekan tombolnya sampai lampu berkedip."
        ) {
            VStack(spacing: 16) {
                ZStack {
                    if phase == .searching { SearchRings() }
                    PhotoSlot(name: "PhotoPuckProduct") {
                        PuckIllustration(ledColor: phase == .idle ? nil : Brand.tealBright)
                            .frame(maxWidth: 240)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)

                if let found, phase == .found {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.safe)
                        Text("\(found.name) ditemukan").font(.headline).foregroundStyle(Brand.ink)
                        Spacer(minLength: 0)
                        Label("\(found.battery)%", systemImage: found.batterySymbol)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2)
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
                    HStack(spacing: 10) { ProgressView(); Text("Mencari…") }
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
    @State private var asking = false

    private let points: [(symbol: String, title: String, detail: String)] = [
        ("speaker.wave.3.fill", "Hanya dari loudspeaker", "Telepon di telinga tidak terdengar."),
        ("text.quote", "Hanya kalimat mencurigakan", "Itu saja yang dikirim ke keluarga."),
        ("bell.badge.fill", "Peringatan lewat notifikasi", "Muncul di atas layar saat menelepon."),
        ("hand.raised.fill", "Anda yang memutuskan", "Rambu tidak menutup telepon Anda."),
    ]

    var body: some View {
        StepScaffold(progress: (3, 5), title: "Sebelum mulai") {
            VStack(spacing: 12) {
                ForEach(points, id: \.title) { point in
                    HStack(spacing: 16) {
                        Image(systemName: point.symbol)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Brand.hero, in: .rect(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.headline).foregroundStyle(Brand.ink)
                            Text(point.detail).font(.subheadline).foregroundStyle(Brand.ink2)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .card(padding: 14)
                    .accessibilityElement(children: .combine)
                }
            }
        } actions: {
            Button {
                // Peringatan datang lewat push, jadi izin notifikasi diminta di sini.
                asking = true
                Task {
                    await model.requestNotifications()
                    asking = false
                    model.onboardingStep = .invite
                }
            } label: { WideLabel(title: "Saya setuju", systemImage: "checkmark") }
                .primaryAction()
                .disabled(asking)
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
            progress: (4, 5),
            title: "Undang pengawas",
            message: "Kirim tautan ke anak Anda."
        ) {
            InviteActions(code: "482913")

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Permintaan masuk")
                if requests.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Menunggu…").font(.subheadline).foregroundStyle(Brand.ink2)
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
            Button { model.onboardingStep = .practiceCall } label: { WideLabel(title: "Lanjut") }
                .primaryAction()
                .disabled(approved.isEmpty)
        }
        .task { await simulateRequests() }
    }

    private func requestRow(_ person: Person) -> some View {
        let isApproved = approved.contains(person.id)
        return HStack(spacing: 12) {
            Avatar(person: person, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline).foregroundStyle(Brand.ink)
                Text(isApproved ? "Terhubung" : person.relation)
                    .font(.subheadline)
                    .foregroundStyle(isApproved ? Brand.safeInk : Brand.ink2)
            }
            Spacer()
            if isApproved {
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

// MARK: - Orang tua: latihan telepon

/// Latihan singkat: ada telepon pura-pura, push Rambu turun, orang tua mengetuknya.
private struct PracticeCallStep: View {
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

/// Jari yang mengetuk berulang, penanda "ketuk di sini".
private struct TapHint: View {
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

// MARK: - Pengawas: masukkan kode

private struct EnterCodeStep: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        StepScaffold(
            progress: (1, 3),
            title: "Masukkan kode",
            message: "6 angka dari aplikasi Rambu orang tua Anda."
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
            if model.pendingInviteCode != nil {
                Label("Kode diisi dari tautan undangan", systemImage: "link")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.safeInk)
            } else {
                Button("Isi kode demo 482 913", systemImage: "wand.and.stars") { code = "482913" }
                    .font(.subheadline.weight(.semibold))
                    .tint(Brand.teal)
            }
        } actions: {
            Button { model.onboardingStep = .guardianProfile } label: { WideLabel(title: "Lanjut") }
                .primaryAction()
                .disabled(code.count < 6)
        }
        .onAppear {
            if let pending = model.pendingInviteCode { code = pending } else { focused = true }
        }
    }
}

// MARK: - Pengawas: latihan memutuskan

/// Contoh peringatan untuk dicoba. Pengawas belajar membaca kalimat lalu memilih.
private struct PracticeAlertStep: View {
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

private struct GuardianWaitingStep: View {
    @Environment(AppModel.self) private var model
    @State private var connected = false

    var body: some View {
        let partner = model.person(for: .richard)
        StepScaffold(
            title: connected ? "Terhubung" : "Menunggu izin",
            message: connected
                ? "Anda menjaga \(model.parent.name) bersama \(partner.name). Cukup satu yang menjawab."
                : "\(model.parent.name) perlu mengizinkan di HP-nya."
        ) {
            // Foto asli: Tia Rahayu, Pexels.
            Image("PhotoGuardian")
                .resizable()
                .scaledToFill()
                .frame(height: 400)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 32, style: .continuous))
                .overlay(alignment: .bottom) {
                    Group {
                        if connected {
                            PushBanner(toast: Toast(id: "contoh", title: "Bahaya: \(model.parent.name) mungkin ditipu",
                                                    body: "Ketuk untuk melihat dan memutuskan.", level: .danger, alertID: nil))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Menunggu \(model.parent.name)…").font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Brand.ink)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.white.opacity(0.92), in: .capsule)
                        }
                    }
                    .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: -8) {
                        Avatar(person: model.person(for: .sinta), size: 40)
                        Avatar(person: model.parent, size: 40)
                    }
                    .padding(6)
                    .background(.white.opacity(0.9), in: .capsule)
                    .padding(14)
                }
                .accessibilityLabel("Seorang perempuan melihat HP")
        } actions: {
            Button { model.completeOnboarding(as: .sinta) } label: { WideLabel(title: "Mulai menjaga") }
                .primaryAction()
                .disabled(!connected)
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: connected)
        .task {
            try? await Task.sleep(for: .seconds(2))
            connected = true
        }
    }
}
