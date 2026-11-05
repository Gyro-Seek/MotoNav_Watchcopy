import UIKit

/// 版本：跟随 App 版本（见 MotoNav/Config.swift，iOS v0.4 新增）
///
/// “分享到 MotoNav”（iOS 分享扩展）：在高德 App 里分享路线时选 MotoNav，这里收到分享的文字 / 链接，
/// 直接打开 MotoNav（motonav://share?t=分享的文字），由 App 去导入路线（ContentView.importShare）。
/// 打不开 App 时把内容复制到剪贴板，提示到 MotoNav 里点“粘贴高德分享的路线”。
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let okButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.10, green: 0.08, blue: 0.14, alpha: 1)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17)
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
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
        collectText { [weak self] text in self?.handle(text) }
    }

    /// 把分享过来的文字、网址都收集起来
    private func collectText(_ done: @escaping (String) -> Void) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var parts: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for item in items {
            if let t = item.attributedContentText?.string, !t.isEmpty { parts.append(t) }
            for p in item.attachments ?? [] {
                for type in ["public.url", "public.plain-text"] where p.hasItemConformingToTypeIdentifier(type) {
                    group.enter()
                    p.loadItem(forTypeIdentifier: type, options: nil) { obj, _ in
                        var s: String?
                        if let u = obj as? URL { s = u.absoluteString }
                        else if let str = obj as? String { s = str }
                        else if let d = obj as? Data { s = String(data: d, encoding: .utf8) }
                        if let s = s, !s.isEmpty { lock.lock(); parts.append(s); lock.unlock() }
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) { done(parts.joined(separator: "\n")) }
    }

    private func handle(_ text: String) {
        guard text.range(of: #"https?://[A-Za-z0-9.\-]*amap\.com/"#, options: .regularExpression) != nil else {
            show("分享的内容里没有高德链接。\n\n在高德 App 里打开规划好的路线，再分享给 MotoNav。")
            return
        }
        var c = URLComponents()
        c.scheme = "motonav"
        c.host = "share"
        var ok = CharacterSet.alphanumerics                // 手动编码：& = + 这些也编码掉，各版本 iOS 都能原样还原
        ok.insert(charactersIn: "-._~")
        guard let enc = text.addingPercentEncoding(withAllowedCharacters: ok) else { fallback(text); return }
        c.percentEncodedQuery = "t=" + enc
        guard let url = c.url else { fallback(text); return }
        openApp(url) { [weak self] ok in
            if ok { self?.extensionContext?.completeRequest(returningItems: nil) } else { self?.fallback(text) }
        }
    }

    /// 分享扩展不能直接打开别的 App（编译时就不让用）：顺着界面往上找到 UIApplication，
    /// 在运行时调用它的 openURL:options:completionHandler: 来打开 MotoNav
    private func openApp(_ url: URL, _ done: @escaping (Bool) -> Void) {
        typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let cur = r {
            if let app = cur as? UIApplication {
                guard app.responds(to: sel) else { break }
                let f = unsafeBitCast(app.method(for: sel), to: OpenFn.self)
                let cb: @convention(block) (Bool) -> Void = { ok in DispatchQueue.main.async { done(ok) } }
                f(app, sel, url as NSURL, NSDictionary(), cb)
                return
            }
            r = cur.next
        }
        done(false)
    }

    private func fallback(_ text: String) {
        UIPasteboard.general.string = text
        show("没能直接打开 MotoNav，链接已经复制好了。\n\n打开 MotoNav，点“粘贴高德分享的路线”就行。")
    }

    private func show(_ msg: String) {
        label.text = msg
        okButton.isHidden = false
    }

    @objc private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
