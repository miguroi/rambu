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
    private var connected = Set<UUID>()
    private var ended = Set<UUID>()

    mutating func reduce(
        id: UUID,
        hasConnected: Bool,
        hasEnded: Bool,
        at: Date
    ) -> [CallActivityEvent] {
        if hasEnded {
            guard ended.insert(id).inserted else { return [] }
            connected.remove(id)
            return [CallActivityEvent(id: id, state: .ended, at: at)]
        }
        guard hasConnected, !ended.contains(id), connected.insert(id).inserted else { return [] }
        return [CallActivityEvent(id: id, state: .connected, at: at)]
    }

    mutating func reconcile(activeCallIDs: Set<UUID>, at: Date) -> [CallActivityEvent] {
        connected.subtracting(activeCallIDs)
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { id in
                guard ended.insert(id).inserted else { return nil }
                connected.remove(id)
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
        observer.setDelegate(nil, queue: nil)
        continuation.finish()
    }
}
