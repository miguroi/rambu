import Foundation
@testable import RambuPuck

struct ScenarioAnalysis: CallAnalysisSource {
    var interval: Duration = .seconds(5)
    var initialDelay: Duration = .milliseconds(1200)

    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error> {
        let lines = Scenario.all.first { $0.id == call.metadata.fixtureID }?.lines ?? []
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

final class CountingFailureSource: CallAnalysisSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let error: BackendAnalysisError

    init(error: BackendAnalysisError) {
        self.error = error
    }

    var invocationCount: Int {
        lock.withLock { count }
    }

    func assessments(for call: CallContext) -> AsyncThrowingStream<ChunkAssessment, Error> {
        lock.withLock { count += 1 }
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
