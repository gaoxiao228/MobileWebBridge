import XCTest
import WebKit
@testable import MobileWebBridge

/// 使用真实 WebKit 验证错误文档、专用动作与原生容器的状态边界。
final class ErrorPageTests: XCTestCase {
    private func controller(enabled: Bool = true) -> MWBWebViewController {
        let url = Bundle.main.resourceURL!.appendingPathComponent("mwb-missing.html")
        return MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: [],
            errorPage: .init(enabled: enabled)))
    }
    private func until(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: timeout), .completed, file: file, line: line)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func overlay(_ c: MWBWebViewController) -> UIView? {
        descendants(c.view).first { $0.accessibilityIdentifier == "mwb-error-overlay" }
    }
    private func button(_ c: MWBWebViewController, _ title: String) -> UIButton {
        descendants(c.view).compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == title }!
    }
    func testH5NavigateToMissingPageShowsVisibleErrorHTML() throws {
        // 直接调用真实 H5 SDK，验证移除首页入口后导航到缺失资源仍能显示错误页。
        let home = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let c = MWBWebViewController(configuration: .init(initialURL: home, allowedOrigins: []))
        let host = ErrorHost(); c.host = host
        let navigation = UINavigationController(rootViewController: c)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        c.loadViewIfNeeded(); until { c.loadState == .loaded }
        let navigated = expectation(description: "H5 发起缺失页面导航")
        c.webView?.evaluateJavaScript("""
            mwb.navigateTo({url: new URL('./mwb-missing.html', window.location.href).href,
                            title: '错误页测试', hidden: false}); true
            """) { value, error in
            XCTAssertNil(error); XCTAssertEqual(value as? Bool, true); navigated.fulfill()
        }
        wait(for: [navigated], timeout: 5)
        until { navigation.viewControllers.count == 2 }
        let child = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertFalse(child === c)
        // XCTest 的临时窗口未必参与 Scene 转场，显式装载已经成功创建的子容器视图。
        child.loadViewIfNeeded()
        until { child.errorPageError != nil }
        XCTAssertEqual(child.errorPageError?.kind, .localResource)
        XCTAssertNotNil(child.onGoHome)
        until {
            self.descendants(child.view).compactMap { $0 as? WKWebView }
                .contains { $0 !== child.webView && !$0.isHidden }
        }
    }
    func testDefaultFailureAndDisabledMode() {
        let c = controller(); c.loadViewIfNeeded()
        until { c.errorPageError != nil }
        XCTAssertNotNil(overlay(c)); XCTAssertFalse(c.isPageReady)
        XCTAssertEqual(c.errorPageError?.kind, .localResource)
        let disabled = controller(enabled: false); disabled.loadViewIfNeeded()
        until { disabled.errorPageError != nil }; XCTAssertNil(overlay(disabled))
    }
    func testRetryUsesFailedGETAndHomeCancelsRetryBeforeCallback() {
        let c = controller(); var calls = 0
        c.onGoHome = { current in
            XCTAssertTrue(Thread.isMainThread); XCTAssertTrue(current === c)
            calls += 1
            current.load(Bundle.main.url(forResource: "index", withExtension: "html")!)
        }
        c.loadViewIfNeeded(); until { c.errorPageError != nil }
        button(c, "重新加载").sendActions(for: .touchUpInside)
        XCTAssertEqual(c.loadState, .loading)
        button(c, "回到首页").sendActions(for: .touchUpInside)
        XCTAssertEqual(calls, 1); XCTAssertNil(overlay(c))
        until { c.loadState == .loaded }; XCTAssertNil(c.errorPageError)
    }
    func testReentrantAndStaleNavigation() {
        let c = controller()
        c.onLoadStateChange = { state in
            if case .failed = state { c.load(Bundle.main.url(forResource: "index", withExtension: "html")!) }
        }
        c.loadViewIfNeeded(); until { c.loadState == .loaded }
        XCTAssertNil(overlay(c)); XCTAssertNil(c.errorPageError)
        c.onLoadStateChange = nil
    }
    func testConfigureEveryContainer() {
        let host = ErrorHost()
        for _ in 0..<2 {
            let c = controller(); c.host = host; c.loadViewIfNeeded()
            XCTAssertNotNil(c.onGoHome)
        }
        XCTAssertEqual(host.configured, 2)
    }
    func testRestrictedResourcesAndRelativeFiles() throws {
        let source = MWBErrorPageSource.builtIn
        let root = try XCTUnwrap(MWBErrorPageResources.root(for: source))
        XCTAssertNotNil(MWBErrorPageResources.file("error.css", root: root))
        for path in ["../index.html", "%2e%2e/index.html", "%252e%252e/index.html", "/etc/passwd", "https://evil.test/a.js"] {
            XCTAssertNil(MWBErrorPageResources.file(path, root: root))
        }
    }
    func testErrorHTMLReadyWithoutBusinessBridge() {
        let c = controller(); c.loadViewIfNeeded(); until { self.overlay(c) != nil }
        let page = descendants(c.view).compactMap { $0 as? WKWebView }.first { $0 !== c.webView }!
        until { !page.isHidden }
        let result = expectation(description: "专用协议可用且无业务桥")
        // 模板必须保留标准模式，且 CSP 仍在文档头生效。
        page.evaluateJavaScript("[window.mwbErrorPage.context.version, typeof window.mwb, document.querySelector('h1').textContent, document.compatMode, !!document.head.querySelector('meta[http-equiv=\"Content-Security-Policy\"]')]") { value, error in
            XCTAssertNil(error)
            let values = value as? [Any]
            XCTAssertEqual(values?[0] as? Int, 1); XCTAssertEqual(values?[1] as? String, "undefined")
            XCTAssertEqual(values?[2] as? String, "页面暂时无法打开")
            XCTAssertEqual(values?[3] as? String, "CSS1Compat")
            XCTAssertEqual(values?[4] as? Bool, true); result.fulfill()
        }
        wait(for: [result], timeout: 5)
    }
    func testCustomHTMLAndMissingResourceFallback() {
        // 用 Demo 随 App 打包的完整自定义目录验证相对 CSS/JS 和专用动作。
        let missing = Bundle.main.resourceURL!.appendingPathComponent("mwb-missing.html")
        let c = MWBWebViewController(configuration: .init(initialURL: missing, allowedOrigins: [],
            errorPage: .init(source: .bundled(bundle: .main, directory: "custom-error", entry: "index.html"))))
        c.loadViewIfNeeded()
        until { c.errorPageError != nil }
        let page = descendants(c.view).compactMap { $0 as? WKWebView }.first { $0 !== c.webView }!
        until { !page.isHidden }
        let result = expectation(description: "自定义模板使用同一受限协议")
        // 接入方的标准 HTML 也不能因容器注入安全策略而变成怪异模式。
        page.evaluateJavaScript("[document.querySelector('h1').textContent, window.mwbErrorPage.context.canGoHome, document.querySelector('.home').hidden, document.compatMode]") { value, error in
            XCTAssertNil(error)
            let values = value as? [Any]
            XCTAssertTrue((values?[0] as? String)?.contains("我们再试一次") == true)
            XCTAssertEqual(values?[1] as? Bool, false); XCTAssertEqual(values?[2] as? Bool, true)
            XCTAssertEqual(values?[3] as? String, "CSS1Compat")
            result.fulfill()
        }
        wait(for: [result], timeout: 5)
        let fallback = MWBWebViewController(configuration: .init(initialURL: missing, allowedOrigins: [],
            errorPage: .init(source: .bundled(bundle: .main, directory: "missing-error", entry: "index.html"))))
        fallback.loadViewIfNeeded(); until { fallback.errorPageError != nil }
        until { self.descendants(fallback.view).compactMap { $0 as? WKWebView }.allSatisfy { $0 === fallback.webView } }
        XCTAssertNotNil(overlay(fallback)); XCTAssertTrue(button(fallback, "重新加载").isEnabled)
        XCTAssertTrue(button(fallback, "回到首页").isHidden)
    }
    func testRendererRecovery() {
        let c = controller(); c.loadViewIfNeeded()
        c.webViewWebContentProcessDidTerminate(c.webView!)
        XCTAssertEqual(c.errorPageError?.kind, .rendererTerminated)
        XCTAssertNotNil(overlay(c)); XCTAssertFalse(c.isPageReady)
    }
    func testCustomDocumentPrefixesPreserveModeAndEnforceCSP() throws {
        // 覆盖 BOM、XML 声明、注释中的假 head、带 > 的属性、省略 head 和无 doctype 模板。
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info = ["CFBundleIdentifier": "test.mwb.error-template", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        let cases = [
            ("\u{FEFF}<!-- <head> is only a comment -->\n<!DOCTYPE HTML><HTML lang='zh-CN'><HEAD data-test='a>b'>", "CSS1Compat"),
            ("<?xml version='1.0'?>\n<!doctype html><html><head>", "CSS1Compat"),
            ("<!doctype html><!-- head omitted -->", "CSS1Compat"),
            ("<html><head>", "BackCompat")
        ]
        for (index, item) in cases.enumerated() {
            let entry = "page\(index).html"
            try (item.0 + "<title>模板测试</title></head><body>错误页</body></html>")
                .write(to: root.appendingPathComponent(entry), atomically: true, encoding: .utf8)
            let c = MWBWebViewController(configuration: .init(initialURL: Bundle.main.resourceURL!.appendingPathComponent("missing.html"),
                allowedOrigins: [], errorPage: .init(source: .bundled(bundle: bundle, directory: "", entry: entry))))
            c.loadViewIfNeeded(); until { c.errorPageError != nil }
            let page = try XCTUnwrap(descendants(c.view).compactMap { $0 as? WKWebView }.first { $0 !== c.webView })
            until { !page.isHidden }
            let checked = expectation(description: "模板 \(index) 保持文档模式及 CSP")
            // data URL 不会请求外网；connect-src none 仍应阻止 fetch。
            page.callAsyncJavaScript("""
                let blocked = false;
                try { await fetch('data:text/plain,blocked'); } catch { blocked = true; }
                return [document.compatMode,
                    !!document.head.querySelector('meta[http-equiv="Content-Security-Policy"]'), blocked];
                """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case let .success(value):
                    let values = value as? [Any]
                    XCTAssertEqual(values?[0] as? String, item.1)
                    XCTAssertEqual(values?[1] as? Bool, true)
                    XCTAssertEqual(values?[2] as? Bool, true)
                case let .failure(error): XCTFail("模板检查失败：\(error)")
                }
                checked.fulfill()
            }
            wait(for: [checked], timeout: 5)
        }
    }
    func testLateStartCannotReopenFailedDocument() {
        let c = controller(); c.loadViewIfNeeded()
        let stale = c.webView!.load(URLRequest(url: c.configuration.initialURL))
        c.load(c.configuration.initialURL)
        until { c.errorPageError != nil }
        let failed = c.loadState
        c.webView(c.webView!, didStartProvisionalNavigation: stale)
        XCTAssertEqual(c.loadState, failed)
        XCTAssertFalse(c.isPageReady)
    }
    func testPostIsNeverReplayed() {
        let error = MWBPageLoadError(kind: .network, url: URL(string: "https://example.test")!,
            method: "POST", message: "failed", httpStatus: nil)
        XCTAssertFalse(error.canRetry)
    }
}

private final class ErrorHost: MWBHostDelegate {
    var configured = 0
    func configureContainer(_ container: MWBWebViewController) {
        configured += 1; XCTAssertEqual(container.loadState, .idle)
        container.onGoHome = { _ in }
    }
}
