import UIKit
import WebKit

/// 仅保留一个从未展示业务内容的备用实例；所有操作与 WebKit 一样限主线程。
final class MWBWebViewPrewarmer: NSObject, WKNavigationDelegate {
    static let shared = MWBWebViewPrewarmer()
    enum State { case empty, scheduled, warming, ready }
    private(set) var state: State = .empty
    private var spare: MWBInteractionWebView?
    private weak var candidate: MWBWebViewController?
    private var idleObserver: CFRunLoopObserver?
    private var timeout: Timer?
    private var navigation: WKNavigation?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let makeWebView: () -> MWBInteractionWebView

    /// 创建依赖保持在内部；默认与业务冷路径共用同一个 WebView 工厂。
    init(makeWebView: @escaping () -> MWBInteractionWebView = MWBInteractionWebView.make) {
        self.makeWebView = makeWebView
        super.init()
        // Scene 后台也清理，避免多窗口宿主只收到 Scene 生命周期时滞留备用。
        observers = [UIApplication.didEnterBackgroundNotification,
                     UIScene.didEnterBackgroundNotification,
                     UIApplication.didReceiveMemoryWarningNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.discard()
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func request(from controller: MWBWebViewController) {
        precondition(Thread.isMainThread)
        guard controller.isEligibleForWebViewPrewarming else { return }
        // 快速切页可在空闲任务执行前替换候选，不能让已离开的页面吞掉新页面的机会。
        if state == .scheduled { candidate = controller; return }
        guard state == .empty else { return }
        state = .scheduled
        candidate = controller
        let token = generation
        // 仅默认模式空闲时启动，滚动跟踪期间不争抢 WebView 初始化资源。
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
                                                         false, 0) { [weak self] _, _ in
            guard let self, self.generation == token, self.state == .scheduled else { return }
            self.idleObserver = nil
            guard self.candidate?.isEligibleForWebViewPrewarming == true else {
                self.discard(); return
            }
            self.candidate = nil
            self.start(token: token)
        }
        idleObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .defaultMode)
    }

    private func start(token: Int) {
        state = .warming
        let webView = makeWebView()
        spare = webView
        webView.navigationDelegate = self
        // 初始 about:blank 会被真实首导航替换；本地空文件则会留下可返回的内部历史。
        navigation = webView.loadHTMLString("<!doctype html><html><head></head><body></body></html>", baseURL: nil)
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.generation == token else { return }
            self.discard()
        }
        timeout = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func takeReady() -> MWBInteractionWebView? {
        precondition(Thread.isMainThread)
        guard state == .ready, let webView = spare else { return nil }
        // 先撤销所有内部任务与委托，再把唯一所有权交给真实业务容器。
        generation += 1
        timeout?.invalidate(); timeout = nil
        webView.navigationDelegate = nil
        spare = nil; navigation = nil
        state = .empty
        return webView
    }

    func discard() {
        precondition(Thread.isMainThread)
        generation += 1
        if let idleObserver { CFRunLoopRemoveObserver(CFRunLoopGetMain(), idleObserver, .defaultMode) }
        idleObserver = nil; candidate = nil
        timeout?.invalidate(); timeout = nil
        spare?.navigationDelegate = nil
        spare?.stopLoading()
        spare = nil; navigation = nil
        state = .empty
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === spare, state == .warming, navigation === self.navigation else { return }
        let token = generation
        webView.evaluateJavaScript("1") { [weak self, weak webView] _, error in
            guard let self, self.generation == token, webView === self.spare, self.state == .warming else { return }
            guard error == nil else { self.discard(); return }
            self.timeout?.invalidate(); self.timeout = nil
            self.state = .ready
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === spare { discard() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === spare { discard() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === spare { discard() }
    }
}
