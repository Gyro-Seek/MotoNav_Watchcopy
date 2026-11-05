import Foundation
var checks = 0
func check(_ p: Bool, _ s: String) { precondition(p, s); checks += 1 }
// Isolated suite: do not modify app/device preferences.
let name = "motonav-map-defaults-\(UUID().uuidString)"
let ud = UserDefaults(suiteName: name)!
defer { ud.removePersistentDomain(forName: name) }
check(MapDefaults.buildings(ud), "new installs default buildings ON")
check(ud.integer(forKey: "map_src") == 3, "new installs default AMap")
ud.removePersistentDomain(forName: name)
ud.set(0, forKey: "map_src"); ud.set(false, forKey: "map_buildings")
check(MapDefaults.buildings(ud), "upgrade enables building extraction")
check(ud.integer(forKey: "map_src") == 3, "upgrade no longer stuck on old automatic provider")
check(ud.integer(forKey: "map_src_before_building_default") == 0, "preserve previous selection")
ud.set(1, forKey: "map_src"); ud.set(false, forKey: "map_buildings")
check(!MapDefaults.buildings(ud), "later explicit building OFF preserved")
check(ud.integer(forKey: "map_src") == 1, "later explicit provider preserved")
check(ud.bool(forKey: MapDefaults.migrationKey), "migration runs once")
print("AMap defaults: \(checks) checks passed")
