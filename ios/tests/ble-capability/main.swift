import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
var probe = BleCapabilityProbe()
check(!probe.next(ready: false, supported: false, now: 0), "Do not query before RX/TX are ready")
check(probe.attempts == 0, "Discovery does not consume retries")
check(probe.next(ready: true, supported: false, now: 0), "Restored HID link without U,1 still probes buildings")
check(!probe.next(ready: true, supported: false, now: 1), "Do not flood the navigation channel")
check(probe.next(ready: true, supported: false, now: 2), "Retry a lost first capability reply")
check(probe.next(ready: true, supported: false, now: 4), "Retry a lost second capability reply")
check(!probe.next(ready: true, supported: false, now: 6), "Bound retries for older firmware")
probe.reset()
check(!probe.next(ready: true, supported: true, now: 10), "Stop after capability acknowledgement")
check(probe.attempts == 0, "Supported link does not consume retries")
check(probe.next(ready: true, supported: false, now: 10), "Allow manual or late-authentication retry")
probe.reset()
check(!probe.next(ready: false, supported: false, now: 10), "Disconnect resets probe without writing")
check(probe.next(ready: true, supported: false, now: 11), "New connection probes immediately")
print("BLE capability: \(checks) checks passed")
