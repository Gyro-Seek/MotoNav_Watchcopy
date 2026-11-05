import Foundation

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    precondition(condition, message)
}
let p = ArrivalPolicy()
check(!p.acceptsCallbacks(0), "idle ignores SDK messages")
check(!p.complete(0, event: .destination), "idle cannot arrive")
let plan = p.preparePlan()
check(p.acceptsCallbacks(plan), "planning accepts route callbacks")
check(!p.acceptsGuidance(plan), "planning cannot send guidance")
check(!p.complete(plan, event: .destination), "route planning cannot celebrate")
let trip = p.begin(simulation: true)
check(!p.acceptsCallbacks(plan), "old planning callbacks ignored")
check(p.acceptsGuidance(trip), "navigation is armed before SDK start")
for distance in [800, 750, 700, 200, 10, 1, 0] {
    let wire = "\(ArrivalPolicy.wireDirection("A")),\(distance)"
    check(!wire.hasPrefix("A"), "destination-ahead at \(distance) metres never completes trip")
    check(p.acceptsGuidance(trip), "destination-ahead preserves active trip")
}
for direction in ["S", "L", "R", "SL", "SR", "U"] {
    check(ArrivalPolicy.wireDirection(direction) == direction, "normal guidance preserved: \(direction)")
}
check(p.complete(trip, event: .emulator), "simulation really ended")
check(!p.complete(trip, event: .emulator), "duplicate simulator end ignored")
check(!p.complete(trip, event: .destination), "second terminal callback ignored")
check(!p.acceptsGuidance(trip), "late navigation info cannot redraw navigation")
check(!p.acceptsCallbacks(trip), "late route and location callbacks ignored")
check(p.canClearArrival(trip), "current arrival timer may clear")
let next = p.begin(simulation: false)
check(!p.canClearArrival(trip), "old four-second timer cannot clear new trip")
check(!p.complete(trip, event: .destination), "old trip cannot finish new trip")
p.cancel(trip)
check(p.acceptsGuidance(next), "old cancellation cannot cancel new trip")
check(!p.complete(next, event: .emulator), "real GPS trip ignores emulator end")
check(p.acceptsGuidance(next), "unexpected emulator end keeps GPS trip active")
check(p.complete(next, event: .destination), "real GPS arrival accepted once")
check(!p.complete(next, event: .destination), "duplicate real arrival ignored")
let cruise = p.beginCruise()
check(!p.canClearArrival(next), "arrival timer cannot clear cruise")
check(p.acceptsCallbacks(cruise), "cruise still receives facilities")
check(!p.acceptsGuidance(cruise), "cruise cannot send turn guidance")
check(!p.complete(cruise, event: .destination), "cruise cannot celebrate arrival")
let manual = p.begin(simulation: true)
p.cancel(manual) // Must happen BEFORE SDK.stopNavi can synchronously emit emulator-end.
check(!p.complete(manual, event: .emulator), "manual exit does not celebrate")
check(!p.complete(manual, event: .destination), "late destination after exit ignored")
check(!p.acceptsGuidance(manual), "late guidance after exit ignored")
let failed = p.begin(simulation: false)
p.cancel(failed)
check(!p.complete(failed, event: .destination), "failed SDK start cannot arrive")
let immediate = p.begin(simulation: true)
check(p.complete(immediate, event: .destination), "synchronous arrival before first guidance is valid")
check(!p.acceptsGuidance(immediate), "start return must not restart ended trip")
let finalPlan = p.preparePlan()
check(!p.canClearArrival(immediate), "planning invalidates prior arrival timer")
check(p.acceptsCallbacks(finalPlan), "new planning remains available after arrival")
print("ArrivalPolicy: \(checks) checks passed")
