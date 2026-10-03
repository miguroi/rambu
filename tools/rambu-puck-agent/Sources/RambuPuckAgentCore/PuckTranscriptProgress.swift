import Foundation

public struct PuckTranscriptProgress: Sendable {
    private var previousTranscript = ""

    public init() {}

    public mutating func line(sequence: Int, cumulativeTranscript: String) -> String {
        let cumulative = cumulativeTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText: String
        if !previousTranscript.isEmpty, cumulative.hasPrefix(previousTranscript) {
            newText = String(cumulative.dropFirst(previousTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            newText = cumulative
        }
        previousTranscript = cumulative
        let displayedText = newText.isEmpty ? "(no speech detected)" : newText
        return "🎙 Heard [chunk \(sequence + 1)]: \(displayedText)"
    }
}
