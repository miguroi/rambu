import Foundation
@testable import RambuPuck

struct ScenarioAnalysis: CallAnalysisSource {
    var interval: Duration = .seconds(5)
    var initialDelay: Duration = .milliseconds(1200)

    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error> {
        let lines = call.scenario?.lines ?? []
        let interval = interval
        let initialDelay = initialDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                var seen = Set<SignalKind>()
                var level = RiskLevel.safe
                for (index, line) in lines.enumerated() {
                    try? await Task.sleep(for: index == 0 ? initialDelay : interval)
                    if Task.isCancelled { break }
                    seen.formUnion(line.signals)
                    level = max(level, RiskRules.level(for: seen))
                    continuation.yield(ChunkAssessment(line: line, level: level, signals: line.signals))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
