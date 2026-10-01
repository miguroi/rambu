import Foundation
import Testing
@testable import RambuPuck

struct CallActivityMonitorTests {
    @Test("A connected call is emitted once despite duplicate callbacks")
    func connectedOnce() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        var reducer = CallActivityReducer()

        #expect(reducer.reduce(id: id, hasConnected: false, hasEnded: false, at: date).isEmpty)
        #expect(reducer.reduce(id: id, hasConnected: true, hasEnded: false, at: date) == [
            CallActivityEvent(id: id, state: .connected, at: date),
        ])
        #expect(reducer.reduce(id: id, hasConnected: true, hasEnded: false, at: date).isEmpty)
    }

    @Test("An ended call is emitted once")
    func endedOnce() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 200)
        var reducer = CallActivityReducer()

        _ = reducer.reduce(id: id, hasConnected: true, hasEnded: false, at: date)
        #expect(reducer.reduce(id: id, hasConnected: true, hasEnded: true, at: date) == [
            CallActivityEvent(id: id, state: .ended, at: date),
        ])
        #expect(reducer.reduce(id: id, hasConnected: true, hasEnded: true, at: date).isEmpty)
    }

    @Test("A call first observed after disconnection does not start protection")
    func endedBeforeConnected() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 300)
        var reducer = CallActivityReducer()

        #expect(reducer.reduce(id: id, hasConnected: true, hasEnded: true, at: date) == [
            CallActivityEvent(id: id, state: .ended, at: date),
        ])
    }
}
