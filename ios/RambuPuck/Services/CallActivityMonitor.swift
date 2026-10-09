import CallKit
import Foundation

enum CallActivityState: Equatable, Sendable {
    case connected
    case ended
}

struct CallActivityEvent: Equatable, Sendable {
    let id: UUID
    let state: CallActivityState
    let at: Date
}

protocol CallActivityMonitoring: Sendable {
    var events: AsyncThrowingStream<CallActivityEvent, Error> { get }
    func refresh()
}

extension CallActivityMonitoring {
    func refresh() {}
}

struct CallActivityReducer: Sendable {
    private static let missingConfirmationInterval: TimeInterval = 1.5

    private var connected = Set<UUID>()
    private var ended = Set<UUID>()
    private var missingSince: [UUID: Date] = [:]

    mutating func reduce(
        id: UUID,
        hasConnected: Bool,
        hasEnded: Bool,
        at: Date
    ) -> [CallActivityEvent] {
        if hasEnded {
            guard ended.insert(id).inserted else { return [] }
            connected.remove(id)
            missingSince.removeValue(forKey: id)
            return [CallActivityEvent(id: id, state: .ended, at: at)]
        }
        guard hasConnected, !ended.contains(id) else { return [] }
        missingSince.removeValue(forKey: id)
        guard connected.insert(id).inserted else { return [] }
        return [CallActivityEvent(id: id, state: .connected, at: at)]
    }

    mutating func reconcile(activeCallIDs: Set<UUID>, at: Date) -> [CallActivityEvent] {
        for id in activeCallIDs {
            missingSince.removeValue(forKey: id)
        }
        return connected.subtracting(activeCallIDs)
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { id -> CallActivityEvent? in
                guard let firstMissingAt = missingSince[id] else {
                    missingSince[id] = at
                    return nil
                }
                guard at.timeIntervalSince(firstMissingAt) >= Self.missingConfirmationInterval else {
                    return nil
                }
                guard ended.insert(id).inserted else { return nil }
                connected.remove(id)
                missingSince.removeValue(forKey: id)
                return CallActivityEvent(id: id, state: .ended, at: at)
            }
    }
}

final class CallKitActivityMonitor: NSObject, CallActivityMonitoring, CXCallObserverDelegate, @unchecked Sendable {
    let events: AsyncThrowingStream<CallActivityEvent, Error>

    private let observer: CXCallObserver
    private let continuation: AsyncThrowingStream<CallActivityEvent, Error>.Continuation
    private let lock = NSLock()
    private var reducer = CallActivityReducer()
    private var reconciliationWorkItem: DispatchWorkItem?

    override init() {
        var captured: AsyncThrowingStream<CallActivityEvent, Error>.Continuation!
        events = AsyncThrowingStream { captured = $0 }
        continuation = captured
        observer = CXCallObserver()
        super.init()
        observer.setDelegate(self, queue: .main)
        for call in observer.calls {
            receive(call)
        }
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        receive(call)
    }

    func refresh() {
        reconcileCurrentCalls()

        reconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileCurrentCalls()
        }
        reconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func reconcileCurrentCalls() {
        let calls = observer.calls
        for call in calls { receive(call) }
        let activeCallIDs = Set(calls.lazy.filter { !$0.hasEnded }.map(\.uuid))
        let values = lock.withLock {
            reducer.reconcile(activeCallIDs: activeCallIDs, at: .now)
        }
        for value in values {
            continuation.yield(value)
        }
    }

    private func receive(_ call: CXCall) {
        let values = lock.withLock {
            reducer.reduce(
                id: call.uuid,
                hasConnected: call.hasConnected,
                hasEnded: call.hasEnded,
                at: .now
            )
        }
        for value in values {
            continuation.yield(value)
        }
    }

    deinit {
        reconciliationWorkItem?.cancel()
        observer.setDelegate(nil, queue: nil)
        continuation.finish()
    }
}
