import SwiftUI

/// Tiruan banner push Rambu, dipakai saat izin notifikasi belum diberikan.
/// Turun dari atas, hilang sendiri, bisa diusap ke atas, dan bisa diketuk.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        Group {
            if let toast = model.toast {
                Button { open(toast) } label: { PushBanner(toast: toast) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .offset(y: min(drag, 0))
                    .gesture(
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation.height }
                            .onEnded { value in if value.translation.height < -30 { model.toast = nil } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: model.toast)
    }

    private func open(_ toast: Toast) {
        model.openToast(toast)
    }
}
