import Foundation
import CoreLocation

let origin = Date(timeIntervalSince1970: 1_800_000_000)
func fix(_ second: Double, speed: Double = 0, lat: Double = 31, accuracy: Double = 5) -> CLLocation {
    CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 121), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed, timestamp: origin.addingTimeInterval(second))
}
func feed(_ timer: CruiseIdleTimer, _ second: Int, speed: Double = 0, lat: Double = 31, accuracy: Double = 5) {
    timer.onFix(fix(Double(second), speed: speed, lat: lat, accuracy: accuracy), now: Double(second), wallTime: origin.addingTimeInterval(Double(second)))
}
let timer = CruiseIdleTimer()
timer.start(at: origin)
for i in 0...599 { feed(timer, i) }
assert(!timer.shouldStop(now: 599))
feed(timer, 600)
assert(timer.shouldStop(now: 600))
assert(!timer.shouldStop(now: 616), "GPS loss must not stop cruise")
timer.start(at: origin)
for i in 0...400 { feed(timer, i) }
feed(timer, 401, speed: 2)
for i in 402...900 { feed(timer, i) }
assert(!timer.shouldStop(now: 900), "Motion resets parking interval")
feed(timer, 901, accuracy: 100)
feed(timer, 902)
assert(!timer.shouldStop(now: 902))
timer.start(at: origin)
for i in 0...599 { feed(timer, i) }
feed(timer, 600, lat: 31.001)
assert(!timer.shouldStop(now: 600), "Slow rolling recognized by displacement")
timer.start(at: origin)
for i in 0...590 { feed(timer, i) }
feed(timer, 610)
assert(!timer.shouldStop(now: 610), "Fix gap resets parking interval")
timer.start(at: origin)
feed(timer, 0)
for i in 1...600 { timer.onFix(fix(0), now: Double(i), wallTime: origin.addingTimeInterval(Double(i))) }
assert(!timer.shouldStop(now: 600), "Cached fixes never count as parking")
timer.stop()
assert(!timer.shouldStop(now: 600))
print("CruiseIdleTimer: 9 checks passed")
