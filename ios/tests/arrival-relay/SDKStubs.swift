import Foundation

@objc protocol AMapNaviDriveManagerDelegate {}
@objc protocol AMapNaviDriveDataRepresentable {}
final class AMapNaviDriveManager: NSObject {}
final class AMapNaviSuggestChangeMainNaviRouteInfo: NSObject {}
final class AMapNaviInfo: NSObject {}
final class AMapNaviLocation: NSObject {}
final class AMapNaviCameraInfo: NSObject {}
final class AMapNaviTrafficFacilityInfo: NSObject {}
final class AMapNaviCruiseInfo: NSObject {}
final class AMapNaviTrafficStatus: NSObject {}

final class NaviBridge {
    let arrival = ArrivalPolicy()
    var calls: [String] = []
    var terminalCount = 0
    var offMain = false
    func acceptsCallback(_ token: UInt64) -> Bool { arrival.acceptsCallbacks(token) }
    func performCallback(_ token: UInt64, _ body: (NaviBridge) -> Void) {
        if !Thread.isMainThread { offMain = true }
        guard arrival.acceptsCallbacks(token) else { return }
        body(self)
    }
    func mnRouteSuccessOld(_ m: AMapNaviDriveManager) { calls.append("mnRouteSuccessOld") }
    func mnRouteSuccessNew(_ m: AMapNaviDriveManager, type: Int) { calls.append("mnRouteSuccessNew") }
    func mnRouteFail(_ m: AMapNaviDriveManager, error: NSError?) { calls.append("mnRouteFail") }
    func mnSound(_ m: AMapNaviDriveManager, text: String?, type: Int) { calls.append("mnSound") }
    func mnSoundPlaying(_ m: AMapNaviDriveManager) -> Bool { calls.append("mnSoundPlaying"); return true }
    func mnArrived(_ m: AMapNaviDriveManager) { calls.append("mnArrived"); if arrival.complete(arrival.generation, event: .destination) { terminalCount += 1 } }
    func mnEmuEnd(_ m: AMapNaviDriveManager) { calls.append("mnEmuEnd"); if arrival.complete(arrival.generation, event: .emulator) { terminalCount += 1 } }
    func mnYaw(_ m: AMapNaviDriveManager) { calls.append("mnYaw") }
    func mnJam(_ m: AMapNaviDriveManager) { calls.append("mnJam") }
    func mnGps(_ m: AMapNaviDriveManager, strength: Int) { calls.append("mnGps") }
    func mnSuggest(_ m: AMapNaviDriveManager, info s: AMapNaviSuggestChangeMainNaviRouteInfo?) { calls.append("mnSuggest") }
    func mnNaviInfo(_ m: AMapNaviDriveManager, info n: AMapNaviInfo?) { calls.append("mnNaviInfo") }
    func mnLocation(_ m: AMapNaviDriveManager, location l: AMapNaviLocation?) { calls.append("mnLocation") }
    func mnCameras(_ m: AMapNaviDriveManager, cams: [AMapNaviCameraInfo]?) { calls.append("mnCameras") }
    func mnLaneShow(_ m: AMapNaviDriveManager, back: String?, select: String?) { calls.append("mnLaneShow") }
    func mnLaneHide(_ m: AMapNaviDriveManager) { calls.append("mnLaneHide") }
    func mnFacilities(_ m: AMapNaviDriveManager, list: [AMapNaviTrafficFacilityInfo]?) { calls.append("mnFacilities") }
    func mnCruiseCams(_ m: AMapNaviDriveManager, list: [AMapNaviTrafficFacilityInfo]?) { calls.append("mnCruiseCams") }
    func mnCruiseInfo(_ m: AMapNaviDriveManager, info c: AMapNaviCruiseInfo?) { calls.append("mnCruiseInfo") }
    func mnTraffic(_ m: AMapNaviDriveManager, status: [AMapNaviTrafficStatus]?) { calls.append("mnTraffic") }
}
