import UIKit
import UserNotifications

/// 「分享到 MotoNav」扩展 v3
///
/// 修复目标：
/// 1. 高德「分享路线」、高德「分享地点」、苹果地图「分享地点」都能进到 MotoNav；
///    不再写死 amap.com，也不再靠固定的 UTI 白名单（苹果地图会带
///    com.apple.mapkit.map-item / public.card / public.vcard，白名单容易漏）。
/// 2. iOS 18 起 Share Extension 已经不能可靠拉起主 App
///    （extensionContext.open 常返回 false，LSApplicationWorkspaceErrorDomain 115），
///    所以不再把「能否跳转」当成功能成败的关键：
///    无论如何都先把分享内容写进剪贴板（手动兜底），再发一条本地通知，
///    通知里直接带上分享正文。用户点通知后主 App 立刻导入并直接开始导航。
/// 3. 仍然保留 extensionContext.open / 响应链两条尝试，
///    iOS 17 及以前、或 iOS 18 上主 App 还在内存里时能真正做到「一点就跳」。
///
/// 主 App 侧对应改动：AppDelegate 接收通知、ContentView 用 onOpenURL /
/// 通知回调自动导入；自动路径不读剪贴板，避免 iOS 16+ 的「允许粘贴」弹窗。
final class ShareViewController: UIViewController {
    /// 和主 App SharePlace.inboxTag 保持一致
    static let inboxTag = "MOTONAVSHARE|"

    private let label = UILabel()
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private var finished = false
    private var started = false
    private var pendingText = ""
    private var pendingURL: URL?

    // 优先读这些类型；其余类型作为兜底，避免苹果地图 / 高德换了 UTI 就丢内容。
    private let preferredTypes = [
        "public.url", "public.plain-text", "public.text", "public.vcard",
        "public.card", "com.apple.mapkit.map-item", "public.image"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.10, green: 0.08, blue: 0.14, alpha: 1)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.text = "正在读取分享内容…"
        openButton.setTitle("打开 MotoNav 并导航", for: .normal)
        openButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        openButton.tintColor = UIColor(red: 1, green: 0.31, blue: 0.71, alpha: 1)
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(tryOpenAgain), for: .touchUpInside)
        doneButton.setTitle("完成", for: .normal)
        doneButton.tintColor = .lightGray
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, openButton, doneButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        DispatchQueue.main.async { [weak self] in
            self?.collectText { text in self?.handle(text) }
        }
    }

    /// 收集所有能转成文字的分享内容（URL 链接、地名、vCard 里的 maps URL、坐标文本）
    private func collectText(_ done: @escaping (String) -> Void) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var parts: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        func add(_ s: String?) {
            guard let s = s, !s.isEmpty else { return }
            lock.lock(); parts.append(s); lock.unlock()
        }

        for item in items {
            add(item.attributedContentText?.string)
            for provider in item.attachments ?? [] {
                // 按实际注册的 UTI 来读，不再只认写死的几种。
                let registered = provider.registeredTypeIdentifiers
                let ordered = preferredTypes.filter { registered.contains($0) }
                    + registered.filter { !preferredTypes.contains($0) }
                // 只挑前 4 个，避免 public.data 之类读出一大坨二进制垃圾
                for type in Array(ordered.prefix(4)) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: type, options: nil) { obj, _ in
                        if let u = obj as? URL { add(u.absoluteString) }
                        else if let s = obj as? String { add(s) }
                        else if let d = obj as? Data {
                            // vCard / plist / 纯文本二进制都在这里；只保留可打印的 UTF-8
                            if let s = String(data: d, encoding: .utf8),
                               s.unicodeScalars.filter({ $0.value < 32 && $0.value != 10 && $0.value != 13 }).isEmpty {
                                add(s)
                            }
                        } else if let d = obj as? NSDictionary { add(d.description) }
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) {
            var seen = Set<String>()
            let uniq = parts.filter { seen.insert($0).inserted }
            done(uniq.joined(separator: "\n"))
        }
    }

    private func handle(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            show("没有读到分享内容。\n请在地图 App 里选「分享」→「MotoNav」，或先「复制链接」再来。")
            return
        }
        pendingText = text
        pendingURL = makeURL(text)

        // 关键：不管能不能跳转，先把内容存好。主 App 回到前台会自动消费。
        UIPasteboard.general.string = Self.inboxTag + text

        // iOS 18 官方建议：扩展用本地通知把用户带回主 App。失败也不影响剪贴板兜底。
        notify()

        guard let url = pendingURL else { saveAndFail(text); return }
        openApp(url) { [weak self] ok in
            guard let self = self else { return }
            if ok { self.finish() }
            else { self.saveAndFail(text) }
        }
    }

    private func makeURL(_ text: String) -> URL? {
        var c = URLComponents()
        c.scheme = "motonav"
        c.host = "share"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let enc = String(text.prefix(12000)).addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        c.percentEncodedQuery = "t=" + enc
        return c.url
    }

    /// 本地通知：「点一下 → 打开 MotoNav → 自动开始导航」
    /// 需要主 App 曾经申请过通知权限（见 MotoNavApp.swift）。没权限 / 被专注模式拦下时，
    /// 用户切回 MotoNav 点首页「粘贴分享的路线 / 地点」也能导入。
    private func notify() {
        let c = UNMutableNotificationContent()
        c.title = "MotoNav 已收到地点"
        c.body = "点此打开 MotoNav，将自动规划并开始导航"
        c.sound = .default
        // 把正文直接随通知带过去：主 App 点通知即可拿到内容，
        // 不用读系统剪贴板，也就不会触发 iOS 16+ 的「允许粘贴」弹窗。
        c.userInfo = ["t": String(pendingText.prefix(3000))]
        let req = UNNotificationRequest(identifier: "motonav-share-\(Int(Date().timeIntervalSince1970))",
                                        content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// 顺序：官方 NSExtensionContext.open → UIWindowScene.open → 响应链 UIApplication。
    /// iOS 18 上它们都可能被拒（LSApplicationWorkspaceErrorDomain 115），
    /// 属预期情况，剪贴板 + 本地通知才是可靠路径。
    private func openApp(_ url: URL, _ done: @escaping (Bool) -> Void) {
        var finalDone = false
        let finish: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !finalDone else { return }
                finalDone = true
                done(ok)
            }
        }
        tryOfficial(url) { [weak self] ok in
            guard let self = self else { finish(ok); return }
            if ok { finish(true); return }
            self.tryScene(url) { ok2 in
                if ok2 { finish(true); return }
                self.legacyOpen(url) { ok3 in finish(ok3) }
            }
        }
    }

    private func tryOfficial(_ url: URL, _ done: @escaping (Bool) -> Void) {
        guard let ctx = extensionContext else { done(false); return }
        var settled = false
        let once: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !settled else { return }
                settled = true
                done(ok)
            }
        }
        ctx.open(url) { ok in once(ok) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { once(false) }
    }

    /// iOS 18 上 UIScene.open 比响应链里的 UIApplication 更可能被放行
    private func tryScene(_ url: URL, _ done: @escaping (Bool) -> Void) {
        guard let scene = view.window?.windowScene else { done(false); return }
        var settled = false
        let once: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !settled else { return }
                settled = true
                done(ok)
            }
        }
        scene.open(url, options: nil) { ok in once(ok) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { once(false) }
    }

    private func legacyOpen(_ url: URL, _ done: @escaping (Bool) -> Void) {
        typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var settled = false
        let settle: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !settled else { return }
                settled = true
                done(ok)
            }
        }
        func call(_ app: UIApplication) {
            guard app.responds(to: sel) else { settle(false); return }
            let f = unsafeBitCast(app.method(for: sel), to: OpenFn.self)
            let cb: @convention(block) (Bool) -> Void = { ok in settle(ok) }
            f(app, sel, url as NSURL, NSDictionary(), cb)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { settle(false) }
        }
        var r: UIResponder? = self
        while let cur = r {
            if let app = cur as? UIApplication { call(app); return }
            r = cur.next
        }
        settle(false)
    }

    private func saveAndFail(_ text: String) {
        UIPasteboard.general.string = Self.inboxTag + text
        show("已收到分享的地点/路线。\n\niOS 18 不允许分享扩展直接跳转：请点通知「MotoNav 已收到地点」自动开始导航；或切回 MotoNav 点首页「粘贴分享的路线 / 地点」。")
        openButton.isHidden = false
        doneButton.isHidden = false
    }

    @objc private func tryOpenAgain() {
        guard let url = pendingURL else { return }
        openApp(url) { [weak self] ok in
            if ok { self?.finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func show(_ msg: String) {
        label.text = msg
        doneButton.isHidden = false
    }

    @objc private func close() {
        finish()
    }
}
