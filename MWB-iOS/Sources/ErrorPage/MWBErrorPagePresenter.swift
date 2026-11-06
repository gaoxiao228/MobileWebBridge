import UIKit
import WebKit

/// 仅管理错误显示和两个专用动作，不注册 DSBridge 或业务插件。
final class MWBErrorPagePresenter: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
    private weak var parent: UIView?
    private let configuration: MWBErrorPageConfiguration
    private let onRetry: () -> Void
    private let onGoHome: () -> Void
    private var overlay: UIView?
    private var page: WKWebView?
    private var error: MWBPageLoadError?
    private var canGoHome = false
    private var retrying = false
    private var session = UUID().uuidString.lowercased()
    private var entryURL: URL?
    private var ready = false
    private var deadline: DispatchWorkItem?
    private let retryButton = UIButton(type: .system)
    private let homeButton = UIButton(type: .system)
    private let messageLabel = UILabel()

    init(parent: UIView, configuration: MWBErrorPageConfiguration, onRetry: @escaping () -> Void, onGoHome: @escaping () -> Void) {
        self.parent = parent; self.configuration = configuration; self.onRetry = onRetry; self.onGoHome = onGoHome
        super.init()
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        homeButton.addTarget(self, action: #selector(home), for: .touchUpInside)
    }
    func show(error: MWBPageLoadError, canGoHome: Bool) {
        self.error = error; self.canGoHome = canGoHome; retrying = false
        if overlay != nil { update(); return }
        guard let parent else { return }
        session = UUID().uuidString.lowercased()
        let layer = UIView(); layer.accessibilityIdentifier = "mwb-error-overlay"
        layer.backgroundColor = UIColor(red: 247/255, green: 250/255, blue: 251/255, alpha: 1)
        layer.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.leadingAnchor.constraint(equalTo: parent.leadingAnchor), layer.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            layer.topAnchor.constraint(equalTo: parent.topAnchor), layer.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
        overlay = layer
        // 在 HTML 可用前就提供原生操作，出错时不递归加载另一份 HTML。
        let title = UILabel(); title.text = "页面暂时无法打开"; title.font = .systemFont(ofSize: 23, weight: .semibold)
        title.textAlignment = .center; title.numberOfLines = 0
        // 兜底背景与 HTML 都固定为浅色，文字不跟随宿主深色模式变白。
        title.textColor = UIColor(red: 20/255, green: 40/255, blue: 56/255, alpha: 1)
        messageLabel.textColor = UIColor(red: 80/255, green: 104/255, blue: 120/255, alpha: 1)
        messageLabel.textAlignment = .center; messageLabel.numberOfLines = 0; messageLabel.font = .systemFont(ofSize: 15)
        let stack = UIStackView(arrangedSubviews: [title, messageLabel, retryButton, homeButton])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        layer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: layer.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: layer.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: layer.trailingAnchor, constant: -28),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            homeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        update()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.setURLSchemeHandler(self, forURLScheme: "mwb-error-resource")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self; web.isHidden = true; web.translatesAutoresizingMaskIntoConstraints = false
        layer.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: layer.topAnchor), web.bottomAnchor.constraint(equalTo: layer.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: layer.leadingAnchor), web.trailingAnchor.constraint(equalTo: layer.trailingAnchor)
        ])
        page = web
        let entry: String
        switch configuration.source { case .builtIn: entry = "index.html"; case let .bundled(_, _, path): entry = path }
        guard let url = URL(string: "mwb-error-resource://\(session)/\(entry)") else { fallback(); return }
        entryURL = url
        let timeout = DispatchWorkItem { [weak self] in self?.fallback() }
        deadline = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        web.load(URLRequest(url: url))
    }
    private var state: [String: Any] {
        ["version": 1, "kind": error?.kind.rawValue ?? "network", "message": error?.userMessage ?? "",
         "httpStatus": error?.httpStatus as Any? ?? NSNull(), "canRetry": error?.canRetry == true,
         "canGoHome": canGoHome, "isRetrying": retrying]
    }
    private func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
    private func update() {
        messageLabel.text = error?.userMessage
        retryButton.setTitle(retrying ? "正在重新加载…" : "重新加载", for: .normal)
        retryButton.isEnabled = !retrying && error?.canRetry == true
        homeButton.setTitle("回到首页", for: .normal); homeButton.isHidden = !canGoHome
        if ready { page?.evaluateJavaScript("window.__mwbErrorRuntime.update(\(json(state)));", completionHandler: nil) }
    }
    @objc private func retry() { if !retrying && error?.canRetry == true { onRetry() } }
    @objc private func home() { if canGoHome { onGoHome() } }
    func setRetrying(_ value: Bool) { retrying = value; update() }
    func updateHomeAvailability(_ value: Bool) { canGoHome = value; update() }
    func dismiss() {
        session = UUID().uuidString.lowercased(); fallback()
        overlay?.removeFromSuperview(); overlay = nil; error = nil
    }
    func dispose() { dismiss() }
    private func fallback() {
        deadline?.cancel(); deadline = nil; ready = false
        // 解除 scheme handler 对展示器的强引用链。
        let old = page; page = nil; old?.navigationDelegate = nil
        old?.stopLoading(); old?.removeFromSuperview()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === page, webView.url == entryURL, !ready,
              let runtimeURL = MWBErrorPageResources.builtInBundle?.url(forResource: "runtime", withExtension: "js"),
              let runtime = try? String(contentsOf: runtimeURL, encoding: .utf8) else { fallback(); return }
        let current = session
        let suffix = json("?session=\(session)")
        webView.evaluateJavaScript("\(runtime)\nwindow.__mwbInstallErrorPage(\(json(state)),function(action){window.location.href='mwb-error-action://'+action.toLowerCase()+\(suffix);});true;") { [weak self, weak webView] result, error in
            guard let self, let webView, self.page === webView, self.session == current else { return }
            if error == nil, result as? Bool == true {
                self.ready = true; self.deadline?.cancel(); self.deadline = nil; webView.isHidden = false
            } else { self.fallback() }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === page, let url = action.request.url else { decisionHandler(.cancel); return }
        if url == entryURL, action.targetFrame?.isMainFrame == true { decisionHandler(.allow); return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let valid = ready && webView.url == entryURL && action.sourceFrame.isMainFrame && action.targetFrame?.isMainFrame == true &&
            url.scheme == "mwb-error-action" && query?.first(where: { $0.name == "session" })?.value == session
        // 先结束 WebKit 决策，原生动作才能安全地同步释放当前错误页。
        decisionHandler(.cancel)
        if valid { if url.host == "retry" { retry() }; if url.host == "gohome" { home() } }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === page { fallback() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === page { fallback() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === page { fallback() } }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard webView === page, let url = urlSchemeTask.request.url, url.host == session,
              let root = MWBErrorPageResources.root(for: configuration.source),
              let file = MWBErrorPageResources.file(String(url.path.dropFirst()), root: root),
              var data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)); return
        }
        let mime: String
        switch file.pathExtension.lowercased() {
        case "html": mime = "text/html"
        case "css": mime = "text/css"
        case "js": mime = "application/javascript"
        case "svg": mime = "image/svg+xml"
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        case "woff": mime = "font/woff"
        case "woff2": mime = "font/woff2"
        case "ttf": mime = "font/ttf"
        default: mime = "application/octet-stream"
        }
        if mime == "text/html" {
            // 自定义 scheme 的 self 语义在不同 WebKit 版本有差别，所有该 scheme 请求仍受根目录限制。
            let csp = "default-src 'none'; script-src mwb-error-resource: 'unsafe-inline'; style-src mwb-error-resource: 'unsafe-inline'; img-src mwb-error-resource: data:; font-src mwb-error-resource: data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
            let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"
            var html = String(data: data, encoding: .utf8) ?? ""
            // 仅越过文档前导、doctype 和 html/head 起始标签，既保留原模式，也在任何内容前安装 CSP。
            // 不在全文搜索 <head>，避免误中注释或脚本里的同名文本；带引号的属性可包含 >。
            let trivia = #"(?:\s|\x{FEFF}|<!--[\s\S]*?-->|<\?xml\s[^>]*>)*"#
            let attributes = #"(?:[^>"']|"[^"]*"|'[^']*')*"#
            let prefix = "\\A\(trivia)(?:<!doctype\\s+\(attributes)>\(trivia))?(?:<html(?=[\\s/>])\(attributes)>\(trivia))?(?:<head(?=[\\s/>])\(attributes)>)?"
            let position = html.range(of: prefix, options: [.regularExpression, .caseInsensitive])?.upperBound ?? html.startIndex
            html.insert(contentsOf: meta, at: position)
            data = Data(html.utf8)
        }
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { /* 本地读取同步完成，无悬挂任务。 */ }
}
