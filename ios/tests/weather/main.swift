import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    precondition(value(), label); checks += 1
}
let zone = TimeZone(identifier: "Asia/Shanghai")!
let reference = QWeatherForecast.timestamp("2026-10-17T15:01+08:00")!
let minute = "2026-10-17T16:00+08:00"
check(QWeatherForecast.timestamp(minute) != nil, "QWeather minute timestamp with offset")
check(QWeatherForecast.timestamp("2026-10-17T08:00Z") == QWeatherForecast.timestamp(minute), "QWeather documented UTC minutes")
check(QWeatherForecast.timestamp("2026-10-17T16:00:00+08:00") == QWeatherForecast.timestamp(minute), "Second-resolution compatibility")
check(QWeatherForecast.timestamp("2026-10-17T08:00:00.123Z") != nil, "Fractional seconds")
check(QWeatherForecast.timestamp("2026-10-17T16:00") == nil, "Do not guess a missing timezone")
check(QWeatherForecast.timestamp("not-a-date") == nil, "Invalid timestamp")
func item(_ time: String, temp: Any = 23, probability: Any? = 0.67) -> [String: Any] {
    var result: [String: Any] = ["forecastTime": time, "condition": ["text": "多云"], "temperature": ["value": temp]]
    if let p = probability { result["precipitation"] = ["probability": p] }
    return result
}
let times = (15...21).map { String(format: "2026-10-17T%02d:00+08:00", $0) }
let result = QWeatherForecast.parse(["hours": times.map { item($0) }], now: reference, timeZone: zone, icon: { _, night in night ? 11 : 1 })
check(result.hours.count == 5 && result.note == nil, "Five future hours survive official minute format")
check(result.hours.map { $0.hour } == [16, 17, 18, 19, 20], "Correct local hours, omit elapsed hour")
check(result.hours[0].probability == 67, "Fractional probability is a percentage")
check(result.hours[3].icon == 11 && result.hours[0].icon == 1, "Day/night icons use forecast time")
let wire = "#W,2,23,15:01,H,\(result.hours.count)" + result.hours.map { "," + $0.wire }.joined()
check(wire == "#W,2,23,15:01,H,5,16,1,23,67,17,1,23,67,18,1,23,67,19,11,23,67,20,11,23,67", "Full five-hour screen message")
let mixed = QWeatherForecast.parse(["hours": [item(times[3]), item(times[1]), item(times[1]), item(times[2])]], now: reference, timeZone: zone, icon: { _, _ in 1 })
check(mixed.hours.map { $0.hour } == [16, 17, 18], "Sort and deduplicate provider data")
let utc = QWeatherForecast.parse(["hours": [item("2026-10-17T08:00Z", temp: "23.6", probability: nil)]], now: reference, timeZone: zone, icon: { _, _ in 1 })
check(utc.hours.first?.hour == 16 && utc.hours.first?.temperature == 24, "UTC conversion and string temperature")
check(utc.hours.first?.probability == -1, "Missing probability stays unknown")
let invalid = QWeatherForecast.parse(["hours": [item("bad"), item(times[1], temp: 500)]], now: reference, timeZone: zone, icon: { _, _ in 1 })
check(invalid.hours.isEmpty && invalid.note?.contains("时间无效") == true && invalid.note?.contains("温度无效") == true, "Explain invalid hourly data")
let stale = QWeatherForecast.parse(["hours": [item(times[0])]], now: reference, timeZone: zone, icon: { _, _ in 1 })
check(stale.hours.isEmpty && stale.note?.contains("已过期") == true, "Stale response is explicit")
let empty = QWeatherForecast.parse(["hours": []], now: reference, icon: { _, _ in 1 })
check(empty.note?.contains("为空") == true, "Empty response is explicit")
let unavailable = QWeatherForecast.parse(nil, now: reference, icon: { _, _ in 1 })
check(unavailable.note != nil && unavailable.hours.isEmpty, "Failed optional request does not fabricate forecast")
check(QWeatherRequestError.http(403).localizedDescription.contains("403"), "Show HTTP service permission status")
check(QWeatherRequestError.http(429).localizedDescription.contains("429"), "Show HTTP quota status")
print("QWeather hourly: \(checks) checks passed")
