import UIKit

/// 「分享到 MotoNav」扩展 v2
///
/// 原版只能收高德「路线」分享（写死了必须含 amap.com 链接），而且只用 responder chain
/// 找 UIApplication 来 openURL —— 这个非官方做法在 iOS 18 上已被系统封堵，
/// 于是分享后跳不回主 App，看起来就像「分享没反应 / 不能导航」。
///
/// v2 改动：
/// 1. 不再要求 amap.com：高德地点、高德路线、苹果地图地点、Google/geo 链接、
///    纯文本里的经纬度、只有地名的情况统统收下，交给主 App 的 SharePlace 去解析；
/// 2. 打开主 App 依次尝试 NSExtensionContext.open（官方）和响应链 UIApplication，
///    并且改在 viewWillAppear 之后才发起（原版在 viewDidLoad 里找，响应链还没建立）；
/// 3. 两条路都走不通（iOS 18 常见）时把内容写进剪贴板并打上标记，
///    用户回到 MotoNav 点首页的「粘贴分享的路线 / 地点」即可，主 App 会自动导航；
/// 4. 主 App 消费后会把标记清掉，不会反复导入。
final class ShareViewController: UIViewController {
    /// 和主 App SharePlace.inboxTag 保持一致
    static let inboxTag = "MOTONAVSHARE|"

    private let label = UILabel()
    private let okButton = UIButton(type: .system)
    private var finished = false
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.10, green: 0.08, blue: 0.14, alpha: 1)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.text = "正在打开 MotoNav…"
        okButton.setTitle("好", for: .normal)
        okButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        okButton.tintColor = UIColor(red: 1, green: 0.31, blue: 0.71, alpha: 1)
        okButton.isHidden = true
        okButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, okButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }

    /// 必须在 VC 已经进入视图层级之后才能走响应链找 UIApplication；
    /// 原版在 viewDidLoad 就找，那时 nextResponder 往往还是空的 —— 这正是老版本跳不回去的原因之一。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !started else { return }
        started = true
        DispatchQueue.main.async { [weak self] in
            self?.collectText { text in self?.handle(text) }
        }
    }

    /// 把分享过来的文字、网址、名片、地址都收集起来（去重）
    private func collectText(_ done: @escaping (String) -> Void) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        // 有的 App 只给 public.url，有的只给 public.plain-text；Apple 地图还会带 public.vcard / public.data
        let types = ["public.url", "public.plain-text", "public.text",
                     "public.vcard", "public.content", "public.data"]
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
                let matched = types.filter { provider.hasItemConformingToTypeIdentifier($0) }
                // public.data / public.content 是万能父类型，会读出二进制垃圾；
                // 只要有更精确的类型就别用它们
                let precise = matched.filter { $0 != "public.data" && $0 != "public.content" }
                let use = precise.isEmpty ? Array(matched.prefix(1)) : precise
                for type in use {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: type, options: nil) { obj, _ in
                        if let u = obj as? URL { add(u.absoluteString) }
                        else if let s = obj as? String { add(s) }
                        else if let d = obj as? Data { add(String(data: d, encoding: .utf8)) }
                        else if let d = obj as? NSDictionary { add(d.description) }
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
            show("没有读到分享内容。\n请在地图 App 里选「分享」→「MotoNav」。")
            return
        }
        guard let url = makeURL(text) else { saveAndFail(text); return }

        // 先暂存一份：万一系统不允许扩展拉起主 App，用户切回 MotoNav 也能一键导入
        UIPasteboard.general.string = Self.inboxTag + text

        openApp(url) { [weak self] ok in
            guard let self = self else { return }
            if ok { self.finish() } else { self.saveAndFail(text) }
        }
    }

    private func makeURL(_ text: String) -> URL? {
        var c = URLComponents()
        c.scheme = "motonav"
        c.host = "share"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // 手动编码：& = + 这些也编码掉，各版本 iOS 都能原样还原
        guard let enc = String(text.prefix(12000)).addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        c.percentEncodedQuery = "t=" + enc
        return c.url
    }

    /// iOS 15~18 对「扩展拉起 containing app」的支持反复变化，不能只赌一种做法。
    /// 顺序：官方 NSExtensionContext.open → 响应链里的 UIApplication。
    private func openApp(_ url: URL, _ done: @escaping (Bool) -> Void) {
        if let ctx = extensionContext {
            var settled = false
            let settle: (Bool) -> Void = { ok in
                DispatchQueue.main.async {
                    guard !settled else { return }
                    settled = true
                    if ok { done(true) } else { self.legacyOpen(url, done) }
                }
            }
            ctx.open(url) { ok in settle(ok) }
            // 某些 iOS 版本上 completion 根本不回调，加个超时继续往下试
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { settle(false) }
            return
        }
        legacyOpen(url, done)
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

        // 顺着响应链找 UIApplication（iOS 17 及以前大多能用；iOS 18 起可能被系统封堵）
        var r: UIResponder? = self
        while let cur = r {
            if let app = cur as? UIApplication { call(app); return }
            r = cur.next
        }
        settle(false)
    }

    private func saveAndFail(_ text: String) {
        UIPasteboard.general.string = Self.inboxTag + text
        show("系统没有允许直接跳转（iOS 18 上常见）。\n\n分享内容已存好：打开 MotoNav，点首页的「粘贴分享的路线 / 地点」，会自动规划并开始导航。")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func show(_ msg: String) {
        label.text = msg
        okButton.isHidden = false
    }

    @objc private func close() {
        finish()
    }
}
