import SwiftUI
import UserNotifications

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 高德导航界面（AMapNaviDriveView）创建时会调用 UIApplication.shared.delegate.window 判断是不是刘海屏。
/// SwiftUI 默认的 AppDelegate 没有 window，会直接崩溃（iOS v0.1.1 点“开始导航”就闪退的原因），
/// 所以这里补一个 AppDelegate，window 返回当前显示的窗口。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shareNotification = NSNotification.Name("MotoNavShareIncoming")
    /// 冷启动时 didReceive 可能早于 ContentView 建立订阅，先存这里
    static var pendingShareText: String?

    var window: UIWindow? {
        get {
            let wins = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return wins.first { $0.isKeyWindow } ?? wins.first
        }
        set {}
    }

    /// 分享扩展在 iOS 18 上无法拉起主 App，只能发本地通知把用户带回来。
    /// 所以主 App 必须先申请通知权限，否则通知会被系统静默丢弃。
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 用户点「MotoNav 已收到地点」通知 → 直接把分享正文交给主界面 → 自动规划并开始导航
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let t = response.notification.request.content.userInfo["t"] as? String, !t.isEmpty {
            AppDelegate.pendingShareText = t
            NotificationCenter.default.post(name: AppDelegate.shareNotification, object: t)
        }
        completionHandler()
    }
}

@main
struct MotoNavApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = Settings.shared

    init() {
        // 高德：key + 隐私合规声明（高德要求在用任何功能前调用；自己用的 App，直接设为已同意）
        AMapServices.shared().apiKey = Settings.shared.amapKeyInUse     // 用户在 App 里填的（iOS v0.7 起没有内置 key；没填时是空的）
        AMapServices.shared().enableHTTPS = true
        AMapNaviManagerConfig.shared().updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapNaviManagerConfig.shared().updatePrivacyAgree(.didAgree)
        AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapSearchAPI.updatePrivacyAgree(.didAgree)
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)

        // 圆屏发来的通知
        BleLink.shared.onNotify = { msg in
            let p = msg.split(separator: ",").map(String.init)
            if p.first == "BOOT", p.count >= 2, let id = Int(p[1]) { Settings.shared.bootReply(id); return }
            if p.count >= 3, p[0] == "T", p[1] == "M" { MusicBridge.shared.handle(p[2]); return }
            if p.first == "T", p.count >= 2 {
                switch p[1] {
                case "W": Weather.shared.request()                    // 滑到了天气页
                case "A": break                                       // 按住接电话：iOS 不允许 App 接电话
                default: break
                }
            }
        }
        BleLink.shared.connect()
        LocationService.shared.start()
        Settings.shared.startDayNight()                 // 夜间配色、亮度按日出日落自动切换（每分钟检查）
        NaviBridge.shared.attach()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(AmapCaptureSurface().frame(width: 1, height: 1))
                .preferredColorScheme(settings.uiLight ? .light : .dark)
        }
    }
}
