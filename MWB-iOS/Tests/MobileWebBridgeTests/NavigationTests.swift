import XCTest
import UIKit
@testable import MobileWebBridge

final class NavigationTests: XCTestCase {
    func testConfigurationDefaultsToWildcardAndPreservesExplicitRestrictions() throws {
        // 不传来源时默认放开 HTTP(S)，显式空集合仍可限制为包内页面。
        let url = try XCTUnwrap(URL(string: "https://example.com/app"))
        XCTAssertEqual(MWBConfiguration(initialURL: url).allowedOrigins, ["*"])
        XCTAssertEqual(try XCTUnwrap(MWBConfiguration.make(initialURLString: url.absoluteString)).allowedOrigins, ["*"])
        XCTAssertTrue(MWBConfiguration(initialURL: url, allowedOrigins: []).allowedOrigins.isEmpty)
        XCTAssertEqual(MWBConfiguration(initialURL: url, allowedOrigins: ["https://example.com"]).allowedOrigins,
                       ["https://example.com"])
    }

    func testWildcardTrustsAllHTTPOriginsIncludingMixedConfiguration() {
        // 单独的星号允许任意 HTTP(S) 来源，包括后续重定向到的新来源。
        for origins in [Set(["*"]), Set(["https://app.example.test", "*"])] {
            let policy = MWBNavigationPolicy(allowedOrigins: origins)
            for address in ["https://example.com/app", "http://other.example.test/path",
                            "https://other.example.test:8443/redirect"] {
                XCTAssertTrue(policy.isTrusted(URL(string: address)!), address)
            }
        }
    }

    func testWildcardPreservesSchemeAndLocalFileBoundaries() {
        // 星号不能绕过协议限制或已有的包内文件目录边界。
        let root = Bundle.main.bundleURL
        let policy = MWBNavigationPolicy(allowedOrigins: ["*"], localRoot: root)
        XCTAssertTrue(policy.isTrusted(root.appendingPathComponent("index.html")))
        for address in ["javascript:alert(1)", "data:text/html,hello", "about:blank",
                        "ftp://example.com/a", "https:/missing-host", "file:///tmp/outside.html"] {
            XCTAssertFalse(policy.isTrusted(URL(string: address)!), address)
        }
        XCTAssertFalse(MWBNavigationPolicy(allowedOrigins: ["*"]).isTrusted(root.appendingPathComponent("index.html")))
    }

    func testPartialWildcardDoesNotTrustSubdomains() {
        // 本次仅支持完整的星号，其他配置继续精确比较来源。
        let policy = MWBNavigationPolicy(allowedOrigins: ["https://*.example.com"])
        XCTAssertFalse(policy.isTrusted(URL(string: "https://app.example.com")!))
        XCTAssertFalse(MWBNavigationPolicy(allowedOrigins: []).isTrusted(URL(string: "https://example.com")!))
    }

    func testMissingLocalPageUnderSymlinkRootCanReachLoadFailure() throws {
        // iOS 安装路径可能经过符号链接；缺失的包内入口必须进入加载失败，而非被误判越界。
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("App.app", isDirectory: true)
        let alias = base.appendingPathComponent("installed-app", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        try manager.createSymbolicLink(at: alias, withDestinationURL: root)
        try Data("index".utf8).write(to: root.appendingPathComponent("index.html"))
        let policy = MWBNavigationPolicy(allowedOrigins: [], localRoot: alias)

        XCTAssertTrue(policy.isTrusted(alias.appendingPathComponent("index.html")))
        XCTAssertTrue(policy.isTrusted(alias.appendingPathComponent("mwb-missing.html")))
        XCTAssertTrue(policy.isTrusted(alias.appendingPathComponent("missing/subpage.html")))
        XCTAssertFalse(policy.isTrusted(base.appendingPathComponent("outside.html")))
        XCTAssertFalse(policy.isTrusted(alias.appendingPathComponent("../outside.html")))

        // 真实指向包外的链接和目标不存在的链接仍须拒绝，不能为错误示例放宽目录边界。
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try manager.createSymbolicLink(at: root.appendingPathComponent("dangling"),
            withDestinationURL: outside.appendingPathComponent("absent"))
        XCTAssertFalse(policy.isTrusted(alias.appendingPathComponent("escape/missing.html")))
        XCTAssertFalse(policy.isTrusted(alias.appendingPathComponent("dangling/missing.html")))
    }

    func testWebContainerHandlesJavaScriptDialogsBeforeDSBridgeFallback() {
        // DSBridge 的旧版 UIAlertView 在 iOS 27 上崩溃，容器必须接管 JS 对话框。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.webView?.dsuiDelegate === controller)
    }

    func testWebContainerBlocksPinchZoomAndLongPressMenus() {
        // 容器需阻止双指缩放和链接菜单，同时在页面中阻止文字长按菜单。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        controller.loadViewIfNeeded()
        let webView = controller.webView!
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)

        // WebKit 会重新启用手势识别器；验证每个加载页面都得到 viewport 约束。
        XCTAssertTrue(webView.configuration.userContentController.userScripts.contains {
            $0.source.contains("maximum-scale=1") && $0.source.contains("user-scalable=no")
        })
        XCTAssertFalse(webView.allowsLinkPreview)
        XCTAssertTrue(webView.uiDelegate?.responds(to: NSSelectorFromString(
            "webView:contextMenuConfigurationForElement:completionHandler:")) == true)
        XCTAssertTrue(webView.configuration.userContentController.userScripts.contains {
            $0.source.contains("contextmenu") && $0.source.contains("-webkit-touch-callout")
        })
        let inspected = expectation(description: "page receives interaction restrictions")
        webView.evaluateJavaScript("""
            (() => ({
              viewport: document.querySelector('meta[name="viewport"]')?.content || '',
              menuBlocked: !document.dispatchEvent(new MouseEvent('contextmenu', {
                bubbles: true, cancelable: true
              }))
            }))()
            """) { value, error in
            XCTAssertNil(error)
            let result = value as? [String: Any]
            XCTAssertTrue((result?["viewport"] as? String)?.contains("maximum-scale=1") == true)
            XCTAssertTrue((result?["viewport"] as? String)?.contains("user-scalable=no") == true)
            XCTAssertEqual(result?["menuBlocked"] as? Bool, true)
            inspected.fulfill()
        }
        wait(for: [inspected], timeout: 5)
    }

    func testBackButtonFallsBackWhenPageHasNoHandler() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = UIViewController()
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(controller, animated: false)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        let button = controller.navigationItem.leftBarButtonItem
        XCTAssertNotNil(button)
        button?.target?.perform(button?.action)
        let popped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.viewControllers.count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [popped], timeout: 2), .completed)
    }

    func testUnsupportedNavigationThemeReturnsError() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let adapter = MWBBridgeAdapter(controller: controller)
        let replied = expectation(description: "theme rejects unsupported icon button")
        adapter.setNavigationBarTheme(["actionIcon": "base64"] ) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1004)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 2)
    }

    func testNavigationThemeCreatesTextActionButtonAndCanRemoveIt() {
        // 右上角文字按钮属于当前控制器；传入空标题应清除它。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let adapter = MWBBridgeAdapter(controller: controller)

        let added = expectation(description: "text action added")
        adapter.setNavigationBarTheme(["actionTxt": "保存", "actionExt": "draft-42",
                                       "color": "112233", "titleColor": "ffffff"]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            added.fulfill()
        }
        wait(for: [added], timeout: 2)
        XCTAssertEqual(controller.navigationItem.rightBarButtonItem?.title, "保存")
        // 十六进制解析得到 RGB 色空间，按颜色分量验证可见色值。
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(navigation.navigationBar.tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 1, accuracy: 0.001)
        XCTAssertEqual(green, 1, accuracy: 0.001)
        XCTAssertEqual(blue, 1, accuracy: 0.001)
        XCTAssertEqual(alpha, 1, accuracy: 0.001)

        let removed = expectation(description: "text action removed")
        adapter.setNavigationBarTheme(["actionTxt": ""]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            removed.fulfill()
        }
        wait(for: [removed], timeout: 2)
        XCTAssertNil(controller.navigationItem.rightBarButtonItem)
    }

    func testNavigationThemeRestoresRootAfterChildReturns() {
        // 子页使用共享 UINavigationController；返回首页时不能保留子页隐藏与改色设置。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let child = MWBWebViewController(configuration: root.configuration)
        let navigation = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        root.beginAppearanceTransition(true, animated: false)
        root.endAppearanceTransition()
        navigation.pushViewController(child, animated: false)
        XCTAssertTrue(navigation.topViewController === child)
        let replied = expectation(description: "theme applied to child")
        let adapter = MWBBridgeAdapter(controller: child)
        adapter.setNavigationBarTheme([
            "hidden": true, "color": "112233", "titleColor": "ffffff"
        ]) { _, _ in replied.fulfill() }
        wait(for: [replied], timeout: 2)
        XCTAssertTrue(navigation.isNavigationBarHidden)

        navigation.popViewController(animated: false)
        XCTAssertTrue(navigation.topViewController === root)
        // 此测试窗口没有 Scene，显式推进返回首页的外观生命周期。
        root.beginAppearanceTransition(true, animated: false)
        root.endAppearanceTransition()
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    func testUnsupportedNavigateOptionsReturnError() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let adapter = MWBBridgeAdapter(controller: controller)
        let replied = expectation(description: "navigate rejects unsupported option")
        adapter.navigateTo(["url": url.absoluteString, "showBackButton": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1004)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 2)
    }

    func testNavigateToHidesNavigationByDefaultAndCanShowItExplicitly() {
        // 新容器默认隐藏原生导航栏，传 hidden=false 可显示；返回首页恢复原状态。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let navigation = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.setNavigationBarHidden(false, animated: false)
        root.loadViewIfNeeded()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            root.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        root.rememberNavigationBarState()

        func open(_ options: [String: Any]) -> MWBWebViewController {
            let replied = expectation(description: "navigateTo replied")
            MWBBridgeAdapter(controller: root).navigateTo(options) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
                replied.fulfill()
            }
            wait(for: [replied], timeout: 5)
            let child = navigation.topViewController as! MWBWebViewController
            // 无 UIWindowScene 的测试窗口需手动推进页面外观生命周期。
            child.beginAppearanceTransition(true, animated: false)
            child.endAppearanceTransition()
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                navigation.transitionCoordinator == nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
            return child
        }

        _ = open(["url": url.absoluteString, "title": "子页"])
        XCTAssertTrue(navigation.isNavigationBarHidden)
        navigation.popToRootViewController(animated: false)
        XCTAssertTrue(navigation.topViewController === root)
        root.beginAppearanceTransition(true, animated: false)
        root.endAppearanceTransition()
        XCTAssertFalse(navigation.isNavigationBarHidden)

        _ = open(["url": url.absoluteString, "title": "预览", "hidden": false])
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    func testHiddenNavigationAllowsEdgePopAndRestoresHostGestureDelegate() {
        // 隐藏栏及自定义返回按钮不能禁用系统边缘返回，离开后须恢复宿主委托。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = UIViewController()
        let child = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let navigation = UINavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        let gesture = navigation.interactivePopGestureRecognizer!
        let originalDelegate = gesture.delegate
        gesture.isEnabled = false
        navigation.pushViewController(child, animated: false)
        child.initialNavigationBarHidden = true
        child.beginAppearanceTransition(true, animated: false)
        child.endAppearanceTransition()

        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertNotNil(child.navigationItem.leftBarButtonItem)
        XCTAssertTrue(gesture.isEnabled)
        XCTAssertTrue(gesture.delegate === child)
        XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), true)

        navigation.pushViewController(UIViewController(), animated: false)
        // 非栈顶控制器不能开始返回；宿主页不继承 MWB 的委托和 enabled 设置。
        if gesture.delegate === child {
            XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), false)
        }
        child.beginAppearanceTransition(false, animated: false)
        child.endAppearanceTransition()
        XCTAssertTrue(gesture.delegate === originalDelegate)
        XCTAssertFalse(gesture.isEnabled)
    }

    func testEdgePopDelegateSurvivesNestedPagesAndRestoresAfterPop() {
        // 模拟新页先出现、旧页后消失，最后 pop 到根页时仍恢复 UIKit 原始委托。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        let gesture = navigation.interactivePopGestureRecognizer!
        let originalDelegate = gesture.delegate
        let first = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let second = MWBWebViewController(configuration: first.configuration)
        navigation.pushViewController(first, animated: false)
        first.beginAppearanceTransition(true, animated: false)
        first.endAppearanceTransition()
        navigation.pushViewController(second, animated: false)
        second.beginAppearanceTransition(true, animated: false)
        second.endAppearanceTransition()
        first.beginAppearanceTransition(false, animated: false)
        first.endAppearanceTransition()
        XCTAssertTrue(gesture.delegate === second)
        XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), true)

        // pop 后 navigationController 可能已经为 nil，仍必须恢复原始识别器状态。
        let delegate = gesture.delegate
        navigation.popToRootViewController(animated: false)
        second.beginAppearanceTransition(false, animated: false)
        second.endAppearanceTransition()
        XCTAssertEqual(delegate?.gestureRecognizerShouldBegin?(gesture), false)
        XCTAssertTrue(gesture.delegate === originalDelegate)
    }

    func testOnlyExactTrustedOriginCanUseBridge() {
        let policy = MWBNavigationPolicy(allowedOrigins: ["https://example.com"])

        XCTAssertTrue(policy.isTrusted(URL(string: "https://example.com/app")!))
        XCTAssertFalse(policy.isTrusted(URL(string: "https://evil.example.com/app")!))
        XCTAssertFalse(policy.isTrusted(URL(string: "http://example.com/app")!))
    }

    func testControllerRejectsUntrustedTopLevelNavigation() {
        let configuration = MWBConfiguration(
            initialURL: URL(string: "https://example.com")!,
            allowedOrigins: ["https://example.com"]
        )
        let controller = MWBWebViewController(configuration: configuration)

        controller.load(URL(string: "https://evil.example.com")!)

        if case .failed = controller.loadState {
            // 拒绝页面时记录失败状态，避免宿主误以为正在加载。
        } else {
            XCTFail("Untrusted page was not rejected")
        }
    }
}
