import UIKit
import WebKit

/// MWB 页面加载状态，便于宿主展示自己的加载和错误界面。
public enum MWBLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// 宿主可直接放入导航栈的 Swift Web 容器。
open class MWBWebViewController: UIViewController {
    public let configuration: MWBConfiguration
    let pluginSnapshot: MWBPluginSnapshot
    private(set) var pluginSession: MWBPluginSession!
    var pluginBridgeSource: URL?
    var pluginBridgeReply: MWBJSCallback?
    private var pluginDocumentURL: URL?

    /// 仅本次 DSBridge prompt 的主 frame 可调用业务网关。
    var isPluginBridgeTrusted: Bool {
        guard !hasFailedDocument, let source = pluginBridgeSource else { return false }
        return isTrusted(source)
    }
    func beginPluginDocument(_ url: URL) {
        guard !hasFailedDocument, isTrusted(url) else { invalidatePluginDocument(); return }
        pluginDocumentURL = url
        pluginSession.beginDocument(url: url)
    }
    /// 失败文档不能通过迟到脚本重新建立业务桥身份。
    private var hasFailedDocument: Bool {
        if abandonedNavigationPreparation { return true }
        if case .failed = loadState { return true }
        return false
    }
    // 文档代次同时隔离迟到的绘制完成与旧 JS 回复。
    private(set) var documentRevision = 0
    private var abandonedNavigationPreparation = false
    private var wasReplaced = false
    var pendingNavigation: MWBNavigationPreparation?
    weak var navigationPreparation: MWBNavigationPreparation?

    var canStartPreparedNavigation: Bool {
        guard let window = viewIfLoaded?.window, !window.isHidden,
              (window.windowScene.map { $0.activationState == .foregroundActive }
                ?? (UIApplication.shared.applicationState == .active)),
              presentedViewController == nil, transitionCoordinator == nil,
              navigationController?.transitionCoordinator == nil,
              !isBeingDismissed, !isMovingFromParent else { return false }
        return navigationController.map { $0.topViewController === self && $0.presentedViewController == nil } ?? true
    }

    /// 取消离屏目标时立即撤销其桥接会话，迟到脚本不能继续调用宿主插件。
    func abandonNavigationPreparation() {
        abandonedNavigationPreparation = true
        webView?.stopLoading()
        invalidatePluginDocument()
    }

    /// UIKit 外观回调可能稍后才结束；从返回栈移除时立即撤销旧页的桥接身份。
    func retireAfterReplacement() {
        wasReplaced = true
        webView?.stopLoading()
        invalidatePluginDocument()
        errorPresenter?.dispose()
    }

    private func invalidatePluginDocument() {
        documentRevision += 1
        pendingNavigation?.cancel(deliverReply: false)
        navigationPreparation?.documentChanged()
        hasRequestedPrewarming = false
        isPageReady = false
        pluginDocumentURL = nil
        pluginSession?.invalidate()
    }
    /// 在首次加载视图前设置；状态相同时不重复通知，回调在主线程执行。
    public var onLoadStateChange: ((MWBLoadState) -> Void)?
    /// 每个主文档首次就绪时通知，不重放历史；闭包捕获宿主时请使用弱引用。
    public var onPageReady: (() -> Void)?
    public private(set) var isPageReady = false
    public private(set) var loadState: MWBLoadState = .idle {
        didSet {
            if oldValue != loadState { onLoadStateChange?(loadState) }
            // 宿主回调可重入 load；准备器读取当前状态而非外层旧值。
            navigationPreparation?.stateChanged()
            requestWebViewPrewarmingIfEligible()
        }
    }
    /// 首页由业务方决定；传入当前容器，避免子页回调捕获父页。
    public var onGoHome: ((MWBWebViewController) -> Void)? {
        didSet { errorPresenter?.updateHomeAvailability(onGoHome != nil) }
    }
    public private(set) var errorPageError: MWBPageLoadError?
    private var errorPresenter: MWBErrorPagePresenter?
    private var retrying = false
    private var loadingURL: URL?
    private var loadingMethod: String? = "GET"
    private var navigationGeneration = 0
    private var activeNavigation: WKNavigation?
    private var requestedNavigation: WKNavigation?
    public private(set) var webView: DWKWebView?
    public weak var host: MWBHostDelegate?
    private let navigationPolicy: MWBNavigationPolicy
    private var bridgeAdapter: MWBBridgeAdapter?
    private var networkObserver: NSObjectProtocol?
    private var appObservers: [NSObjectProtocol] = []
    private var visibleAtMs: Int64?
    private var hasBeenVisible = false
    private var isContainerVisible = false
    private var hasRequestedPrewarming = false

    /// 每次真正稳定显示最多申请一次；弱引用任务不能延长业务容器生命周期。
    var isEligibleForWebViewPrewarming: Bool {
        configuration.webViewPrewarmingEnabled && isContainerVisible
            && viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive
            && transitionCoordinator == nil && navigationController?.transitionCoordinator == nil
            && viewIfLoaded?.window?.isHidden == false
            && (loadState == .loaded || isPageReady)
    }

    private func requestWebViewPrewarmingIfEligible() {
        guard !hasRequestedPrewarming, isEligibleForWebViewPrewarming else { return }
        hasRequestedPrewarming = true
        MWBWebViewPrewarmer.shared.request(from: self)
    }
    private var hasStartedNavigation = false
    var initialPageOverride: URL?
    var initialNavigationBarHidden: Bool?
    private var navigationBarState: NavigationBarState?
    private var navigationActionExt: String?
    private weak var managedPopGesture: UIGestureRecognizer?
    private weak var previousPopGestureDelegate: UIGestureRecognizerDelegate?
    private var previousPopGestureEnabled = true


    // UINavigationController 的导航栏由多个页面共用；每页保存自己的可见样式。
    private struct NavigationBarState {
        let hidden: Bool
        let backgroundColor: UIColor?
        let titleTextAttributes: [NSAttributedString.Key: Any]?
        let tintColor: UIColor?
        let standardAppearance: UINavigationBarAppearance
        let scrollEdgeAppearance: UINavigationBarAppearance?
        let compactAppearance: UINavigationBarAppearance?
    }

    /// 公开指定初始化器，允许外部子类继承或调用 super.init(configuration:)。
    public init(configuration: MWBConfiguration) {
        let pluginSnapshot = MWB.pluginSnapshot()
        self.pluginSnapshot = pluginSnapshot
        self.configuration = configuration
        self.navigationPolicy = MWBNavigationPolicy(
            allowedOrigins: configuration.allowedOrigins,
            localRoot: Bundle.main.resourceURL
        )
        super.init(nibName: nil, bundle: nil)
        self.pluginSession = MWBPluginSession(snapshot: pluginSnapshot, controller: self,
            trustedURL: { [weak self] in
                guard let self, let url = self.pluginDocumentURL, self.isTrusted(url),
                      self.isTrusted(self.webView?.url ?? url) else { return nil }
                return url
            }, event: { [weak self] message in
                self?.webView?.evaluateJavaScript(MWBPluginJavaScript.event(message), completionHandler: nil)
            })
        self.pluginSession.notifyPageReady = { [weak self] in
            guard let self, self.pluginSession.identity != nil,
                  self.loadState == .loading || self.loadState == .loaded else {
                return .failure(-1104, "Document is no longer active")
            }
            // 先设置再回调；宿主可同步导航，回调后不得重新写回旧文档状态。
            if !self.isPageReady {
                let document = self.pluginSession.identity
                self.isPageReady = true
                self.pageDidBecomeReady()
                // 扩展方法可同步导航；旧文档不能继续触发闭包。
                if self.pluginSession.identity == document && self.isPageReady {
                    self.onPageReady?()
                    self.requestWebViewPrewarmingIfEligible()
                }
            }
            return .success()
        }
    }

    /// 子类可处理当前主文档就绪；状态和去重已由内部完成，无需调用 super。
    open func pageDidBecomeReady() {}

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Use init(configuration:)")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // 仅 ready 实例可同步移交；未命中直接冷启动，不阻塞导航转场。
        let webView = (configuration.webViewPrewarmingEnabled ? MWBWebViewPrewarmer.shared.takeReady() : nil)
            ?? MWBInteractionWebView.make()
        webView.pluginController = self
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.dsuiDelegate = self
        let bridgeAdapter = MWBBridgeAdapter(controller: self)
        webView.addJavascriptObject(bridgeAdapter, namespace: "mwb")
        self.bridgeAdapter = bridgeAdapter
        _ = MWBNetworkState.shared
        networkObserver = NotificationCenter.default.addObserver(
            forName: MWBNetworkState.changed, object: nil, queue: .main
        ) { [weak self] notification in
            self?.sendEvent("networkStatusChange", data: ["networkType": notification.object as? String ?? "unknown"])
        }
        appObservers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.sendEvent("appShow")
                self?.hasRequestedPrewarming = false
                self?.requestWebViewPrewarmingIfEligible()
            },
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification,
                                                   object: nil, queue: .main) { [weak self] notification in
                guard let self, let scene = notification.object as? UIWindowScene,
                      scene === self.viewIfLoaded?.window?.windowScene else { return }
                self.hasRequestedPrewarming = false
                self.requestWebViewPrewarmingIfEligible()
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.sendEvent("appHide")
            }
        ]
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.webView = webView
        errorPresenter = MWBErrorPagePresenter(parent: view, configuration: configuration.errorPage,
            onRetry: { [weak self] in self?.retryFailedPage() }, onGoHome: { [weak self] in self?.goHomeFromError() })
        host?.configureContainer(self)
        // configureContainer 可重入取消任务；取消后不能再启动初始加载。
        guard !abandonedNavigationPreparation else { return }
        load(initialPageOverride ?? configuration.initialURL)
    }

    /// 装载指定页面，后续安全策略会在导航委托中继续校验重定向。
    public func load(_ url: URL) {
        guard !abandonedNavigationPreparation else { return }
        guard isTrusted(url) else {
            // 已有有效页面时拒绝新目标，但不遮盖当前文档。
            if loadState == .idle { failLoad(kind: .blockedNavigation, message: "Untrusted URL: \(url.absoluteString)", url: url) }
            return
        }
        navigationGeneration += 1
        requestedNavigation = nil; activeNavigation = nil
        webView?.stopLoading()
        retrying = false; errorPresenter?.dismiss(); errorPageError = nil
        webView?.isHidden = false
        loadingURL = url; loadingMethod = "GET"
        invalidatePluginDocument()
        requestedNavigation = startRequest(url)
        loadState = .loading
    }

    private func startRequest(_ url: URL) -> WKNavigation? {
        if url.isFileURL, let root = Bundle.main.resourceURL {
            return webView?.loadFileURL(url, allowingReadAccessTo: root)
        }
        return webView?.load(URLRequest(url: url))
    }

    public func reload() {
        guard !abandonedNavigationPreparation else { return }
        if errorPageError != nil { retryFailedPage(); return }
        guard let webView else { return }
        navigationGeneration += 1
        invalidatePluginDocument()
        requestedNavigation = webView.reload()
        loadState = .loading
    }

    private func retryFailedPage() {
        guard let failure = errorPageError, !retrying, failure.canRetry, isTrusted(failure.url) else { return }
        navigationGeneration += 1
        retrying = true; errorPresenter?.setRetrying(true)
        invalidatePluginDocument()
        loadingURL = failure.url; loadingMethod = "GET"
        requestedNavigation = startRequest(failure.url)
        loadState = .loading
    }

    private func goHomeFromError() {
        guard let callback = onGoHome, let failure = errorPageError else { return }
        if retrying {
            navigationGeneration += 1
            let generation = navigationGeneration
            requestedNavigation = nil; activeNavigation = nil
            webView?.stopLoading(); invalidatePluginDocument()
            retrying = false; errorPresenter?.setRetrying(false)
            loadState = .failed(failure.message)
            if generation != navigationGeneration || errorPageError == nil { return }
        }
        callback(self)
    }

    private func failLoad(kind: MWBPageLoadError.Kind, message: String, url: URL? = nil, method: String? = nil, status: Int? = nil) {
        guard let target = url ?? loadingURL ?? webView?.url else { return }
        invalidatePluginDocument()
        requestedNavigation = nil; activeNavigation = nil
        retrying = false
        webView?.stopLoading()
        let failure = MWBPageLoadError(kind: kind, url: target, method: method ?? loadingMethod, message: message, httpStatus: status)
        errorPageError = failure
        if configuration.errorPage.enabled {
            webView?.isHidden = true
            errorPresenter?.show(error: failure, canGoHome: onGoHome != nil)
        }
        // 通知放最后，宿主可同步导航或销毁，旧处理不回写新状态。
        loadState = .failed(message)
    }

    private func navigationFailed(_ navigation: WKNavigation?, error: Error) {
        guard let navigation, navigation === (requestedNavigation ?? activeNavigation), loadState == .loading else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        let kind: MWBPageLoadError.Kind
        if loadingURL?.isFileURL == true { kind = .localResource }
        else if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut { kind = .timeout }
        else if nsError.domain == NSURLErrorDomain && (-1206 ... -1200).contains(nsError.code) { kind = .tls }
        else { kind = .network }
        failLoad(kind: kind, message: error.localizedDescription)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let navigationBarState {
            restoreNavigationBarState(navigationBarState)
        } else {
            // 新容器首次出现时采用 navigateTo 传入的导航栏状态，再保存本页快照。
            if let initialNavigationBarHidden {
                navigationController?.setNavigationBarHidden(initialNavigationBarHidden, animated: false)
            }
            rememberNavigationBarState()
        }
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "返回", style: .plain, target: self, action: #selector(handleBackButton)
            )
        }
    }

    /// 主题方法修改当前页后更新快照，供子页返回时恢复当前页样式。
    func rememberNavigationBarState() {
        guard let navigationController else { return }
        let bar = navigationController.navigationBar
        navigationBarState = NavigationBarState(
            hidden: navigationController.isNavigationBarHidden,
            backgroundColor: bar.backgroundColor,
            titleTextAttributes: bar.titleTextAttributes,
            tintColor: bar.tintColor,
            standardAppearance: bar.standardAppearance.copy(),
            scrollEdgeAppearance: bar.scrollEdgeAppearance?.copy(),
            compactAppearance: bar.compactAppearance?.copy()
        )
    }

    private func restoreNavigationBarState(_ state: NavigationBarState) {
        guard let navigationController else { return }
        let bar = navigationController.navigationBar
        bar.backgroundColor = state.backgroundColor
        bar.titleTextAttributes = state.titleTextAttributes
        bar.tintColor = state.tintColor
        bar.standardAppearance = state.standardAppearance
        bar.scrollEdgeAppearance = state.scrollEdgeAppearance
        bar.compactAppearance = state.compactAppearance
        navigationController.setNavigationBarHidden(state.hidden, animated: false)
    }

    /// 右上角文字按钮归当前页面所有，点击时只通知当前可信网页。
    func configureNavigationAction(title: String?, ext: String?) {
        navigationActionExt = ext
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: title, style: .plain, target: self, action: #selector(handleNavigationAction)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc private func handleNavigationAction() {
        guard let url = webView?.url, isTrusted(url) else { return }
        var payload: [String: Any] = [:]
        if let navigationActionExt { payload["actionExt"] = navigationActionExt }
        callJSHandler("navigationActionClick", arguments: [payload])
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isContainerVisible = true
        hasRequestedPrewarming = false
        // didAppear 可能仍在 UIKit 转场收尾中；下一主线程机会再校验，避免漏掉已快速加载的页面。
        DispatchQueue.main.async { [weak self] in self?.requestWebViewPrewarmingIfEligible() }
        if !hasBeenVisible {
            // 首次出现在屏幕上才开始白屏计时，返回当前控制器时不重置。
            hasBeenVisible = true
            visibleAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            publishVisibleAt()
        }
        enableInteractivePopGesture()
        sendEvent("pageShow")
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isContainerVisible = false
        pendingNavigation?.cancel()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isContainerVisible = false
        restoreInteractivePopGesture()
        sendEvent("pageHide")
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            invalidatePluginDocument()
            errorPresenter?.dispose()
        }
    }

    /// 隐藏导航栏或自定义返回按钮时，仍使用 UIKit 自带的边缘交互返回。
    private func enableInteractivePopGesture() {
        guard let navigationController,
              navigationController.topViewController === self,
              navigationController.viewControllers.count > 1,
              let gesture = navigationController.interactivePopGestureRecognizer,
              gesture.delegate !== self else { return }
        // UIKit 的出现/消失回调顺序可能交错；不能把上一 MWB 页当作宿主委托保存。
        if let previousPage = gesture.delegate as? MWBWebViewController {
            previousPopGestureDelegate = previousPage.previousPopGestureDelegate
            previousPopGestureEnabled = previousPage.previousPopGestureEnabled
        } else {
            previousPopGestureDelegate = gesture.delegate
            previousPopGestureEnabled = gesture.isEnabled
        }
        managedPopGesture = gesture
        gesture.delegate = self
        gesture.isEnabled = true
    }

    private func restoreInteractivePopGesture() {
        guard let gesture = managedPopGesture,
              gesture.delegate === self else { return }
        gesture.delegate = previousPopGestureDelegate
        gesture.isEnabled = previousPopGestureEnabled
    }

    @objc private func handleBackButton() {
        guard let webView else { navigationController?.popViewController(animated: true); return }
        var resolved = false
        // 页面缺少 SDK 或 JS 句柄时 DSBridge 可能不回调，原生超时回退。
        let fallback = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !resolved else { return }
            resolved = true
            fallback()
        }
        webView.callHandler("mwb.backBtnPressed") { value in
            guard !resolved else { return }
            resolved = true
            if value as? Bool != true { fallback() }
        }
    }

    public func isTrusted(_ url: URL) -> Bool {
        !wasReplaced && navigationPolicy.isTrusted(url)
    }

    deinit {
        errorPresenter?.dispose()
        pluginSession?.invalidate()
        if let networkObserver { NotificationCenter.default.removeObserver(networkObserver) }
        appObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 原生业务可通过此方法调用 H5 注册的 MWB 句柄。
    public func callJSHandler(_ name: String, arguments: [Any] = [],
                              completion: ((Any?) -> Void)? = nil) {
        webView?.callHandler("mwb.\(name)", arguments: arguments, completionHandler: completion)
    }

    /// 统一向 JS SDK 分发容器生命周期及宿主推送事件。
    public func sendEvent(_ name: String, data: Any? = nil) {
        callJSHandler("dispatchEvent", arguments: [["name": name, "data": data ?? NSNull()]])
    }

    private func publishVisibleAt() {
        guard let visibleAtMs, let webView, let url = webView.url, isTrusted(url) else { return }
        // 可见与加载完成可能任一先到；重复注入让 H5 总能收到同一个起点。
        let script = "window.__mwbDemoVisibleAt=\(visibleAtMs);window.dispatchEvent(new Event('mwb-visible'));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

// 接管 DSBridge 的网页对话框，避免其旧版 UIAlertView 在 iOS 27 上崩溃。
extension MWBWebViewController: WKUIDelegate {
    public final func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard view.window != nil else { completionHandler(); return }
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    public final func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard view.window != nil else { completionHandler(false); return }
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    public final func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                        defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                        completionHandler: @escaping (String?) -> Void) {
        guard view.window != nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}

extension MWBWebViewController: WKNavigationDelegate {
    public final func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, isTrusted(url) else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            // hash / SPA 路由保留实例；主文档替换在放行时立即撤销旧授权。
            var old = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            var next = URLComponents(url: url, resolvingAgainstBaseURL: false)
            old?.fragment = nil; next?.fragment = nil
            let fragmentOnly = old != nil && old?.url == next?.url
                && webView.url != url && navigationAction.navigationType != .reload
            if !fragmentOnly {
                loadingURL = url
                loadingMethod = navigationAction.request.httpMethod
                invalidatePluginDocument()
                // 放行新文档后，旧导航即使迟到失败也不再代表当前页面。
                activeNavigation = nil
            }
        }
        decisionHandler(.allow)
    }

    public final func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                              decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            // 先结束 WebKit 策略决策，再通知宿主，允许回调同步重入导航。
            decisionHandler(.cancel)
            failLoad(kind: .http, message: "HTTP \(response.statusCode)", url: response.url, status: response.statusCode)
            return
        }
        decisionHandler(.allow)
    }

    public final func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // 失败已经撤销导航身份；迟到的 start 不能重新开放隐藏的业务文档。
        guard navigation != nil, !hasFailedDocument || retrying else { return }
        if let requestedNavigation, requestedNavigation !== navigation { return }
        requestedNavigation = nil
        activeNavigation = navigation
        invalidatePluginDocument()
        if hasBeenVisible && hasStartedNavigation {
            // 同一容器的后续整页导航重新计算可见白屏。
            visibleAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        }
        hasStartedNavigation = true
        loadState = .loading
    }

    public final func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failLoad(kind: .rendererTerminated, message: "Web content process terminated")
    }

    public final func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    public final func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === (requestedNavigation ?? activeNavigation), loadState == .loading else { return }
        errorPresenter?.dismiss(); errorPageError = nil; retrying = false
        webView.isHidden = false
        publishVisibleAt()
        loadState = .loaded
    }

    public final func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }
}


extension MWBWebViewController: UIGestureRecognizerDelegate {
    /// 根页、非栈顶页及尚未结束的转场均不能启动交互返回。
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return gestureRecognizer === navigationController.interactivePopGestureRecognizer
            && navigationController.topViewController === self
            && navigationController.viewControllers.count > 1
            && navigationController.transitionCoordinator == nil
    }
}
