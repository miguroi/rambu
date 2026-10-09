import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RambuPuckWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RambuCallLiveActivity()
    }
}

/// Status Rambu saat orang tua menelepon, di Lock Screen dan Dynamic Island.
/// Karena layar telepon milik iOS, di sinilah peringatan Rambu terlihat selama panggilan.
struct RambuCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RambuCallAttributes.self) { context in
            LockScreenCallView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.white.opacity(0.94))
                .activitySystemActionForegroundColor(Brand.teal)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MascotView(pose: state.pose, onDark: true, animated: false, sign: state.signLevel)
                        .frame(width: 50, height: 60)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: 56, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.islandTitle)
                            .font(.headline)
                            .foregroundStyle(state.accent)
                        Text(state.decisionTitle == nil ? state.headline : "Dari \(state.decidedBy ?? "pengawas")")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(state.decisionAdvice ?? state.level.parentAdvice)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(state.level == .review ? Brand.signalInk : .white, state.accent)
            } compactTrailing: {
                Text(state.compactTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(state.accent)
            } minimal: {
                Image(systemName: state.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(state.level == .review ? Brand.signalInk : .white, state.accent)
            }
            .keylineTint(state.accent)
        }
    }
}

private struct LockScreenCallView: View {
    let attributes: RambuCallAttributes
    let state: RambuCallAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MascotView(pose: state.pose, animated: false, sign: state.signLevel)
                .frame(width: 54, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: state.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(state.level == .review ? Brand.signalInk : .white, state.accentOnLight)
                    Text(state.islandTitle)
                        .font(.headline)
                        .foregroundStyle(state.accentOnLight)
                }
                Text(state.decisionAdvice ?? state.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(2)
                Text("\(attributes.parentName) · \(attributes.channel)")
                    .font(.caption)
                    .foregroundStyle(Brand.ink3)
            }
            Spacer(minLength: 0)
            Text(attributes.startedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Brand.ink3)
                .frame(maxWidth: 56, alignment: .trailing)
        }
        .padding(16)
    }
}

private extension RambuCallAttributes.ContentState {
    var isScamDecision: Bool { decisionIsScam == true }
    var isSafeDecision: Bool { decisionIsScam == false }

    var pose: MascotPose {
        if isScamDecision { return .stop }
        if isSafeDecision { return .calm }
        switch level {
        case .safe: return isListening ? .calm : .rest
        case .review: return .check
        case .danger: return .stop
        }
    }

    /// Papan yang dipegang maskot: ikut keputusan pengawas kalau sudah ada.
    var signLevel: RiskLevel {
        if isScamDecision { return .danger }
        if isSafeDecision { return .safe }
        return level
    }

    var symbol: String {
        if isScamDecision { return RiskLevel.danger.symbol }
        if isSafeDecision { return RiskLevel.safe.symbol }
        return level == .safe ? "waveform.circle.fill" : level.symbol
    }

    var islandTitle: String {
        if let decisionTitle { return decisionTitle }
        return level == .safe ? "Rambu mendengarkan" : level.title
    }

    var compactTitle: String {
        if isScamDecision { return "Tutup" }
        return level.shortTitle
    }

    var accent: Color {
        if isScamDecision { return Color(hex: 0xFF6B5E) }
        if isSafeDecision { return Color(hex: 0x5FD49B) }
        switch level {
        case .safe: return Color(hex: 0x5FD4C0)
        case .review: return Brand.signal
        case .danger: return Color(hex: 0xFF6B5E)
        }
    }

    var accentOnLight: Color {
        if isScamDecision { return Brand.danger }
        if isSafeDecision { return Brand.safe }
        return level == .safe ? Brand.teal : level.tint
    }
}
