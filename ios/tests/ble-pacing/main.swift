import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
var pace = BleWritePacer()
for _ in 0..<BleWritePacer.burst { check(pace.take(now: 0), "Initial bounded burst") }
check(!pace.take(now: 0), "Ready callbacks cannot reset the shared burst budget")
check(!pace.take(now: 0.019), "Navigation pump calls also respect the cooldown")
check(pace.delay(now: 0.019) > 0, "Exhausted budget schedules a later pump")
check(pace.take(now: 0.02), "Queued data continues after the interval")
pace.reset()
check(pace.take(now: 0.021), "Reconnect receives a fresh budget")

// Exercise a large transfer against the real firmware ring capacity and 30-message drain limit,
// with slower 80ms frame processing. Unpaced writes overflow this receiver in one pump call.
pace.reset()
var time = 0.0, drainedAt = 0.0, received = 0, delivered = 0, peak = 0, overflow = false
while delivered < 1000 {
    if time - drainedAt >= 0.08 { delivered += min(30, received); received = max(0, received - 30); drainedAt = time }
    while delivered + received < 1000, pace.take(now: time) {
        received += 1; peak = max(peak, received); overflow = overflow || received > 47
    }
    time += 0.001
    precondition(time < 10, "Pacing must not stall a transfer")
}
check(!overflow, "Map and image writes do not overflow the firmware RX ring")
check(delivered == 1000, "Every fragment reaches the receiver")
check(peak <= 30, "Receiver keeps capacity for navigation commands")
check(time < 4, "Paced thousand-fragment transfer remains usable")
let transferSeconds = time
print("BLE pacing: \(checks) checks passed; peak RX queue \(peak), 1000 fragments \(String(format: "%.2f", transferSeconds))s")
