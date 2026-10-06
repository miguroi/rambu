import SwiftUI

public struct TranscriptWindow: View {
    @ObservedObject private var model: PuckControllerViewModel

    public init(model: PuckControllerViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.transcriptLines.isEmpty {
                        Text("Belum ada transkrip.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.transcriptLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: model.transcriptLines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}
