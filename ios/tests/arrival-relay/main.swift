import Foundation

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    precondition(condition, message)
}
let bridge = NaviBridge()
let manager = AMapNaviDriveManager()
let first = bridge.arrival.begin(simulation: true)
let old = NaviSessionCallbacks(bridge: bridge, token: first)
check(old.asDelegate != nil, "runtime delegate protocol registered")
check(old.asRepresentative != nil, "runtime data protocol registered")
old.mnNaviInfo(manager, info: nil)
check(bridge.calls == ["mnNaviInfo"], "current guidance delivered immediately on main")
old.mnEmuEnd(manager)
old.mnArrived(manager)
old.mnEmuEnd(manager)
old.mnNaviInfo(manager, info: nil)
old.mnLocation(manager, location: nil)
old.mnRouteSuccessOld(manager)
check(bridge.terminalCount == 1, "terminal callback delivered only once")
check(bridge.calls == ["mnNaviInfo", "mnEmuEnd"], "closed trip drops all subsequent SDK callbacks")
let second = bridge.arrival.begin(simulation: false)
let current = NaviSessionCallbacks(bridge: bridge, token: second)
old.mnArrived(manager)
old.mnRouteSuccessNew(manager, type: 0)
check(bridge.arrival.acceptsGuidance(second), "retained old delegate cannot finish new trip")
check(bridge.calls.count == 2, "old delegate cannot forward route success")
current.mnEmuEnd(manager)
check(bridge.terminalCount == 1 && bridge.arrival.acceptsGuidance(second), "GPS mode ignores emulator end")
bridge.arrival.cancel(second)
current.mnEmuEnd(manager) // Simulates stopNavi calling back synchronously after manual exit.
current.mnArrived(manager)
check(bridge.terminalCount == 1, "manual stop gates synchronous end callback")
let planning = bridge.arrival.preparePlan()
let queued = NaviSessionCallbacks(bridge: bridge, token: planning)
let queuedReady = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    queued.mnRouteSuccessOld(manager)
    queuedReady.signal()
}
check(queuedReady.wait(timeout: .now() + 5) == .success, "background callback queued")
let newest = bridge.arrival.begin(simulation: true)
let fresh = NaviSessionCallbacks(bridge: bridge, token: newest)
let before = bridge.calls.count
let delivered = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    fresh.mnNaviInfo(manager, info: nil)
    delivered.signal()
}
check(delivered.wait(timeout: .now() + 5) == .success, "current background callback queued")
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
check(bridge.calls.count == before + 1 && bridge.calls.last == "mnNaviInfo", "main queue drops old planning result and accepts current guidance")
check(!bridge.offMain, "all forwarded callbacks execute on main queue")
fresh.mnArrived(manager)
check(bridge.terminalCount == 2, "new trip can complete normally")
check(!fresh.mnSoundPlaying(manager), "closed delegate does not revive speech")
print("Arrival callback relay: \(checks) checks passed")
