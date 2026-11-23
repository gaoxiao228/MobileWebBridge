import XCTest
import UIKit
import WebKit
@testable import MobileWebBridge

final class NavigationTests: XCTestCase {
    func testStyledDemoPushReplacementAndNativeBackRestoreAppearance() throws {
        // 真实 H5 配置页发起替换，并保存包含导航栏的完整窗口截图。
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        XCTAssertEqual(theme(root, ["hidden": false, "title": "根页", "buttonColor": "008800", "actionTxt": "添加"]), 0)
        let url = root.configuration.initialURL.deletingLastPathComponent().appendingPathComponent("navigation-theme.html")
        func script(_ page: MWBWebViewController, _ source: String) {
            let done = expectation(description: "real Demo interaction")
            page.webView?.evaluateJavaScript(source) { _, error in XCTAssertNil(error); done.fulfill() }
            wait(for: [done], timeout: 5)
        }
        func waitForPage(after previous: MWBWebViewController) throws -> MWBWebViewController {
            let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let page = navigation.topViewController as? MWBWebViewController else { return false }
                return page !== previous && page.loadState == .loaded && navigation.transitionCoordinator == nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 10), .completed)
            return try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        }
        func capture(_ name: String) {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        script(root, "void mwb.navigateTo({url:'\(url.absoluteString)',title:'初始样式',hidden:false,color:'f6fbfa',titleColor:'0b4148',buttonColor:'049f91',buttonBackgroundVisible:false,backButtonStyle:'arrowText',titleFontSize:17,buttonFontSize:16}); 'started';")
        let source = try waitForPage(after: root)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 4/255, green: 159/255, blue: 145/255, alpha: 1))
        // 打开的首帧、后创建的操作按钮与局部更新使用同一背景设置。
        XCTAssertEqual(theme(source, ["actionTxt": "添加"]), 0)
        XCTAssertEqual(theme(source, ["title": "导航栏样式"]), 0)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(root.navigationItem.rightBarButtonItem?.hidesSharedBackground, false)
            XCTAssertEqual(source.navigationItem.leftBarButtonItem?.hidesSharedBackground, true)
            XCTAssertEqual(source.navigationItem.rightBarButtonItem?.hidesSharedBackground, true)
        }
        #endif
        capture("navigation-appearance-initial")
        XCTAssertEqual(theme(source, ["buttonBackgroundVisible": true]), 0)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(source.navigationItem.leftBarButtonItem?.hidesSharedBackground, false)
            XCTAssertEqual(source.navigationItem.rightBarButtonItem?.hidesSharedBackground, false)
        }
        #endif
        script(source, """
            const set=(name,value)=>{const el=document.querySelector(`[name="${name}"]`);el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));};
            const hidden=document.querySelector('[name="hidden"]');hidden.checked=false;hidden.dispatchEvent(new Event('change',{bubbles:true}));
            const background=document.querySelector('[name="buttonBackgroundVisible"]');
            background.checked=false;background.dispatchEvent(new Event('change',{bubbles:true}));
            set('buttonColor','#0066cc');set('titleFontSize','32');set('buttonFontSize','28');set('backButtonText','返回');
            setTimeout(()=>document.querySelector('.theme-replace-page').click(),0); 'started';
            """)
        let target = try waitForPage(after: source)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 0, green: 102/255, blue: 204/255, alpha: 1))
        let font = try XCTUnwrap(navigation.navigationBar.standardAppearance.titleTextAttributes[.font] as? UIFont)
        XCTAssertLessThanOrEqual(font.pointSize, 32)
        capture("navigation-appearance-replacement-large-type")
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(target.navigationItem.leftBarButtonItem?.hidesSharedBackground, true)
        }
        #endif
        let back = try XCTUnwrap(target.navigationItem.leftBarButtonItem?.customView as? UIButton)
        XCTAssertGreaterThanOrEqual(back.bounds.width, 44)
        back.sendActions(for: .touchUpInside)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController === root && navigation.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 0, green: 136/255, blue: 0, alpha: 1))
        capture("navigation-appearance-returned-root")
    }

    func testSeparatorColorPreservesHiddenHostBaseline() throws {
        // 透明色和有效透明阴影图都属于隐藏基线；无像素 UIImage() 会被新 UIKit 当成 nil。
        for useImage in [false, true] {
            let navigation = UINavigationController(rootViewController: UIViewController())
            navigation.loadViewIfNeeded()
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            if useImage {
                appearance.shadowImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
                    .image { _ in }.withRenderingMode(.alwaysOriginal)
            } else { appearance.shadowColor = .clear }
            navigation.navigationBar.standardAppearance = appearance
            var snapshot = MWBNavigationBarSnapshot(navigation)
            func checkHidden(_ value: UINavigationBarAppearance) {
                if useImage { XCTAssertEqual(value.shadowImage?.size, CGSize(width: 1, height: 1)) }
                else { XCTAssertEqual(value.shadowColor?.cgColor.alpha ?? 0, 0) }
            }
            checkHidden(snapshot.standard)
            snapshot.apply(.init(color: .white, separatorColor: .red), traits: .init())
            checkHidden(snapshot.standard)
            snapshot.apply(.init(separatorVisible: true, separatorColor: .red), traits: .init())
            XCTAssertEqual(snapshot.standard.shadowColor, .red)
            XCTAssertNil(snapshot.standard.shadowImage)
        }
    }

    func testHostDefaultAndOpeningPatchMergeWithoutChangingSourceDuringPreparation() throws {
        // 真实离屏目标没有 navigationController，早期主题仍须在显示时完整生效。
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let originalTint = navigation.navigationBar.tintColor
        let defaults = MWBNavigationBarAppearance(titleColor: .red, buttonColor: .green,
            backButtonStyle: .arrowText, titleFontSize: 17, buttonFontSize: 16)
        let target = MWBWebViewController(configuration: .init(initialURL: root.configuration.initialURL,
            allowedOrigins: [], navigationBarAppearance: defaults))
        target.configureInitialNavigationBar(try .parse(["titleColor": "0000ff", "separatorVisible": false], strict: true))
        target.initialNavigationBarHidden = false
        target.loadViewIfNeeded()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in target.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        XCTAssertEqual(theme(target, ["titleColor": "ffffff"]), 0)
        XCTAssertEqual(navigation.navigationBar.tintColor, originalTint)
        XCTAssertFalse(navigation.mwbNavigationState.isolated)
        navigation.pushViewController(target, animated: false)
        target.beginAppearanceTransition(true, animated: false); target.endAppearanceTransition()
        XCTAssertEqual(navigation.navigationBar.tintColor, .green)
        XCTAssertTrue(navigation.mwbNavigationState.isolated)
        XCTAssertEqual(navigation.navigationBar.standardAppearance.titleTextAttributes[.foregroundColor] as? UIColor,
                       UIColor(red: 1, green: 1, blue: 1, alpha: 1))
        let back = try XCTUnwrap(target.navigationItem.leftBarButtonItem?.customView as? UIButton)
        // 箭头文字按钮使用 UIButton.Configuration，数据不会写入旧的 UIControl.State 存储。
        let configuration = try XCTUnwrap(back.configuration)
        let backTitle = try XCTUnwrap(configuration.attributedTitle)
        XCTAssertEqual(String(backTitle.characters), "返回")
        XCTAssertNotNil(configuration.image)
        XCTAssertGreaterThanOrEqual(back.bounds.height, 44)
    }

    func testBackgroundParentUpdateRestoresOnlyAfterPopAndReloadClearsDocumentAction() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        XCTAssertEqual(theme(root, ["buttonColor": "049f91", "actionTxt": "根操作", "actionExt": "root"]), 0)
        let child = MWBWebViewController(configuration: root.configuration)
        navigation.pushViewController(child, animated: false)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in child.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        child.beginAppearanceTransition(true, animated: false); child.endAppearanceTransition()
        XCTAssertEqual(theme(child, ["buttonColor": "ff0000", "hidden": false]), 0)
        XCTAssertEqual(theme(root, ["buttonColor": "0000ff", "hidden": true]), 0)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertFalse(navigation.isNavigationBarHidden)
        navigation.popViewController(animated: false)
        root.beginAppearanceTransition(true, animated: false); root.endAppearanceTransition()
        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(root.navigationItem.rightBarButtonItem?.title, "根操作")
        root.load(root.configuration.initialURL)
        XCTAssertNil(root.navigationItem.rightBarButtonItem)
        XCTAssertNil(root.currentNavigationActionExt)
    }

    func testAppearanceValidationAndLegacyIsolationBoundary() throws {
        for params: [String: Any] in [["buttonColor": NSNull()], ["showBackButton": 1], ["separatorVisible": "true"],
            ["backButtonText": " "], ["backButtonStyle": "custom"], ["titleFontWeight": "heavy"],
            ["titleFontSize": true], ["buttonFontSize": 29], ["separatorColor": "#12345678"]] {
            XCTAssertThrowsError(try MWBNavigationBarPatch.parse(params))
        }
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        XCTAssertEqual(theme(root, ["titleColor": "112233"]), 0)
        XCTAssertFalse(navigation.mwbNavigationState.isolated)
        let child = MWBWebViewController(configuration: root.configuration)
        navigation.pushViewController(child, animated: false)
        child.beginAppearanceTransition(true, animated: false); child.endAppearanceTransition()
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 17/255, green: 34/255, blue: 51/255, alpha: 1))
        XCTAssertEqual(theme(child, ["buttonColor": "bad"]), -1001)
        XCTAssertFalse(navigation.mwbNavigationState.isolated)
        let other = UINavigationController(rootViewController: UIViewController())
        XCTAssertFalse(other.mwbNavigationState.isolated)
    }

    private func theme(_ page: MWBWebViewController, _ values: [String: Any]) -> Int? {
        let reply = expectation(description: "theme response")
        var code: Int?
        let adapter = MWBBridgeAdapter(controller: page)
        adapter.setNavigationBarTheme(values) { value, _ in
            code = MWBResult.parse(value)?.errCode
            reply.fulfill()
        }
        wait(for: [reply], timeout: 3)
        withExtendedLifetime(adapter) {}
        return code
    }

    func testIndependentButtonColorSurvivesTitleAndActionUpdates() throws {
        // 标题更新和新建操作按钮都不得覆盖显式按钮色。
        let (window, navigation, page) = try readyNavigationContext()
        defer { window.isHidden = true }
        XCTAssertEqual(theme(page, ["titleColor": "0b4148", "buttonColor": "049f91"]), 0)
        let buttons = UIColor(red: 4/255, green: 159/255, blue: 145/255, alpha: 1)
        XCTAssertEqual(navigation.navigationBar.tintColor, buttons)
        XCTAssertEqual(theme(page, ["titleColor": "ffffff", "actionTxt": "保存"]), 0)
        XCTAssertEqual(navigation.navigationBar.tintColor, buttons)
        XCTAssertEqual(navigation.navigationBar.standardAppearance.titleTextAttributes[.foregroundColor] as? UIColor,
                       UIColor(red: 1, green: 1, blue: 1, alpha: 1))
    }

    func testInvalidAppearanceRejectsWholeThemeAndNavigation() throws {
        // 错误样式不能先改标题，也不能创建/替换目标容器。
        let (window, navigation, page) = try readyNavigationContext()
        defer { window.isHidden = true }
        page.title = "原页"
        XCTAssertEqual(theme(page, ["title": "不应应用", "buttonColor": "bad"]), -1001)
        XCTAssertEqual(theme(page, ["title": "不应应用", "buttonBackgroundVisible": "false"]), -1001)
        XCTAssertEqual(page.title, "原页")
        for method in ["navigateTo", "redirectTo"] {
            let replied = expectation(description: method)
            let adapter = MWBBridgeAdapter(controller: page)
            let callback: MWBJSCallback = { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, -1001)
                replied.fulfill()
            }
            let args: [String: Any] = ["url": page.configuration.initialURL.absoluteString, "titleFontSize": 100]
            if method == "navigateTo" { adapter.navigateTo(args, handler: callback) }
            else { adapter.redirectTo(args, handler: callback) }
            wait(for: [replied], timeout: 3)
            XCTAssertTrue(navigation.topViewController === page)
        }
    }

    func testNavigationCarriesAppearanceBeforeTargetFirstDisplay() throws {
        let (window, navigation, page) = try readyNavigationContext()
        defer { window.isHidden = true }
        let replied = expectation(description: "styled navigation")
        MWBBridgeAdapter(controller: page).navigateTo([
            "url": page.configuration.initialURL.absoluteString, "hidden": false,
            "color": "f6fbfa", "titleColor": "0b4148", "buttonColor": "049f91",
            "backButtonStyle": "arrowText", "backButtonText": "返回", "showBackButton": false,
            "separatorVisible": false, "titleFontSize": 17, "titleFontWeight": "semibold", "buttonFontSize": 16
        ]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 3)
        let child = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertFalse(child === page)
        child.beginAppearanceTransition(true, animated: false)
        child.endAppearanceTransition()
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertNil(child.navigationItem.leftBarButtonItem)
        XCTAssertEqual(navigation.navigationBar.tintColor, UIColor(red: 4/255, green: 159/255, blue: 145/255, alpha: 1))
        XCTAssertEqual(navigation.navigationBar.standardAppearance.shadowColor ?? .clear, .clear)
        XCTAssertTrue(child.navigationItem.hidesBackButton)
    }

    func testRedirectDemoThroughRealJavaScriptBridgeReturnsToSameP() throws {
        // 使用同步到 App 的实际 SDK/H5，覆盖原生桥接、页面身份和完整返回栈。
        let (window, navigation, previous) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        var parts = URLComponents(url: previous.configuration.initialURL, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "mwbRedirect", value: "P")]
        previous.load(try XCTUnwrap(parts.url))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in previous.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        let revision = previous.documentRevision

        func script(_ page: MWBWebViewController, _ source: String) {
            let completed = expectation(description: "real JS bridge invocation")
            page.webView?.evaluateJavaScript(source) { _, error in
                XCTAssertNil(error)
                completed.fulfill()
            }
            wait(for: [completed], timeout: 3)
        }
        func checkHeading(_ page: MWBWebViewController, _ heading: String) {
            let checked = expectation(description: "Demo page identity")
            page.webView?.evaluateJavaScript("document.querySelector('h1').textContent") { value, error in
                XCTAssertNil(error)
                XCTAssertEqual(value as? String, heading)
                checked.fulfill()
            }
            wait(for: [checked], timeout: 3)
        }
        func capture(_ page: MWBWebViewController, _ name: String) {
            let captured = expectation(description: "rendered Demo snapshot")
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            page.webView?.takeSnapshot(with: config) { image, error in
                XCTAssertNil(error)
                if let image {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                } else { XCTFail("Demo snapshot was unavailable") }
                captured.fulfill()
            }
            wait(for: [captured], timeout: 3)
        }

        checkHeading(previous, "页面 P")
        script(previous, """
            const a = new URL(location.href); a.searchParams.set('mwbRedirect', 'A');
            void mwb.navigateTo({url: a.href, hidden: true, waitForReady: true});
            "started";
            """)
        let pushed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController !== previous && navigation.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pushed], timeout: 5), .completed)
        let source = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        checkHeading(source, "页面 A")
        capture(source, "redirect-A-phone")
        script(source, """
            const b = new URL(location.href); b.searchParams.set('mwbRedirect', 'B');
            void mwb.redirectTo({url: b.href, hidden: true, waitForReady: true});
            "started";
            """)
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController !== source && navigation.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 5), .completed)
        let target = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        checkHeading(target, "页面 B")
        capture(target, "redirect-B-phone")
        script(target, "void mwb.navigateBack(); 'started';")
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController === previous && navigation.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        checkHeading(previous, "页面 P")
        XCTAssertEqual(previous.documentRevision, revision)
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testRedirectReplacesCurrentAndBackSkipsSource() throws {
        // P 和 A 均真实可见过；替换后返回的是同一个 P 实例。
        let (window, navigation, previous) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        let source = MWBWebViewController(configuration: previous.configuration)
        navigation.pushViewController(source, animated: false)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let replied = expectation(description: "replacement requested")
        MWBBridgeAdapter(controller: source).redirectTo([
            "url": source.configuration.initialURL.absoluteString, "title": "B", "hidden": false
        ]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 3)
        let child = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.viewControllers.first === previous)
        XCTAssertFalse(child === source)
        XCTAssertEqual(child.title, "B")
        // UIKit 移除回调尚未结束时，已被替换的 A 也不能继续调用原生能力。
        XCTAssertFalse(source.isTrusted(source.configuration.initialURL))
        // 成功代表替换已发起；外观和移除回调由 UIKit 随后完成。
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !navigation.isNavigationBarHidden && source.pluginSession.identity == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 3), .completed)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertNil(source.pluginSession.identity)
        XCTAssertFalse(child.webView === source.webView)
        let back = expectation(description: "B returns to P")
        MWBBridgeAdapter(controller: child).navigateBack(nil) { _, _ in back.fulfill() }
        wait(for: [back], timeout: 3)
        XCTAssertTrue(navigation.topViewController === previous)
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testRedirectRootDefaultsToImmediateEvenWhenTargetCannotLoad() throws {
        // 缺失目标也会立即替换，证明默认和 false 没有偷偷等待加载。
        for explicitFalse in [false, true] {
            let (window, navigation, source) = try readyNavigationContext()
            defer { window.isHidden = true }
            let missing = Bundle.main.resourceURL!.appendingPathComponent("mwb-redirect-missing.html")
            var params: [String: Any] = ["url": missing.absoluteString]
            if explicitFalse { params["waitForReady"] = false }
            let replied = expectation(description: "immediate root replacement")
            MWBBridgeAdapter(controller: source).redirectTo(params) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
                replied.fulfill()
            }
            wait(for: [replied], timeout: 3)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertFalse(navigation.topViewController === source)
            let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                navigation.isNavigationBarHidden
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 3), .completed)
            XCTAssertTrue(navigation.isNavigationBarHidden)
            XCTAssertNil(source.pendingNavigation)
        }
    }

    func testRedirectWaitsForDrawingAndDisposesSourceDocument() throws {
        let (window, navigation, source) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        let host = ReadyNavigationHost(delayMs: 200)
        host.configured = { XCTAssertTrue(navigation.topViewController === source) }
        source.host = host
        MWBBridgeAdapter(controller: source).redirectTo([
            "url": source.configuration.initialURL.absoluteString, "waitForReady": true
        ]) { _, _ in /* 旧文档销毁后，不依赖它继续处理成功回调。 */ }
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController !== source
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 5), .completed)
        let child = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertEqual(child.loadState, .loaded)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertTrue(child.host === host)
        XCTAssertNil(source.pendingNavigation)
        XCTAssertNil(source.pluginSession.identity)
        XCTAssertFalse(child.webView?.canGoBack ?? true)
    }

    func testRedirectPreparationFailureAndTimeoutKeepSource() throws {
        for timeout in [false, true] {
            let (window, navigation, source) = try readyNavigationContext()
            defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
            let host = ReadyNavigationHost(delayMs: timeout ? 3500 : 0)
            source.host = host
            let target = timeout ? source.configuration.initialURL :
                Bundle.main.resourceURL!.appendingPathComponent("mwb-redirect-failure.html")
            let failed = expectation(description: "preparation fails without replacing A")
            MWBBridgeAdapter(controller: source).redirectTo(["url": target.absoluteString, "waitForReady": true]) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, -1002)
                failed.fulfill()
            }
            wait(for: [failed], timeout: 5)
            XCTAssertTrue(navigation.topViewController === source)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertNil(source.pendingNavigation)
            XCTAssertNotNil(source.pluginSession.identity)
            XCTAssertNil(host.child?.pluginSession.identity)
        }
    }

    func testRedirectPreparationRejectsConcurrentNavigationAndCancelsOnBackground() throws {
        let (window, navigation, source) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 500)
        source.host = host
        let adapter = MWBBridgeAdapter(controller: source)
        let cancelled = expectation(description: "replacement cancelled")
        adapter.redirectTo(["url": source.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1005)
            cancelled.fulfill()
        }
        let duplicate = expectation(description: "navigateTo cannot race replacement")
        adapter.navigateTo(["url": source.configuration.initialURL.absoluteString]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1004)
            duplicate.fulfill()
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }
        wait(for: [duplicate, cancelled], timeout: 3)
        XCTAssertTrue(navigation.topViewController === source)
        XCTAssertNil(source.pendingNavigation)
    }

    func testRedirectRejectsInvalidParametersAndMissingNavigation() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let source = MWBWebViewController(configuration: .init(initialURL: url))
        let adapter = MWBBridgeAdapter(controller: source)
        let cases: [([String: Any], Int)] = [
            (["url": url.absoluteString, "hidden": 1], -1001),
            (["url": url.absoluteString, "waitForReady": "true"], -1001),
            (["url": url.absoluteString, "title": false], -1001),
            (["url": url.absoluteString, "isPopUp": true], -1004),
            (["url": url.absoluteString], -1004),
            (["url": "javascript:alert(1)"], -1001)
        ]
        for (params, expected) in cases {
            let rejected = expectation(description: "unsupported replacement")
            adapter.redirectTo(params) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, expected)
                rejected.fulfill()
            }
            wait(for: [rejected], timeout: 2)
        }
        XCTAssertNil(source.presentedViewController)
    }

    func testRedirectRejectsSourceThatIsNoLongerTheTopPage() throws {
        // 隐藏的 P 不能把当前 A 替换掉，更不能往自己的位置插入新页。
        let (window, navigation, previous) = try readyNavigationContext()
        defer { window.isHidden = true }
        let current = MWBWebViewController(configuration: previous.configuration)
        navigation.pushViewController(current, animated: false)
        let rejected = expectation(description: "hidden source cannot replace top")
        MWBBridgeAdapter(controller: previous).redirectTo(["url": previous.configuration.initialURL.absoluteString]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1004)
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 3)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.topViewController === current)
    }

    func testNavigateWaitsForDrawingBeforePushAndPreservesHostCallbacks() throws {
        // 目标容器已加载才允许开始push；不要求H5报告业务ready。
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        let host = ReadyNavigationHost()
        root.host = host
        let replied = expectation(description: "prepared navigation")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            let child = navigation.topViewController as? MWBWebViewController
            XCTAssertFalse(child === root)
            XCTAssertEqual(child?.loadState, .loaded)
            XCTAssertFalse(child?.isPageReady ?? true)
            XCTAssertFalse(child?.webView?.canGoBack ?? true)
            XCTAssertEqual(host.loadedCount, 1)
            XCTAssertEqual(host.configuredCount, 1)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
    }

    func testNavigateWithoutWaitStillStartsImmediately() throws {
        // 目标故意不存在：无需依赖 WebKit 与 UIKit 的竞争时序，即可证明默认路径不等待加载成功。
        let missingURL = Bundle.main.resourceURL!.appendingPathComponent("mwb-immediate-missing.html")
        for option in [false, true] {
            // 各参数使用独立导航上下文，避免上次 pop 的外观回调与下一次 push 重叠。
            let (window, navigation, root) = try readyNavigationContext()
            defer { window.isHidden = true }
            let replied = expectation(description: "old immediate behavior")
            var params: [String: Any] = ["url": missingURL.absoluteString]
            if option { params["waitForReady"] = false }
            MWBBridgeAdapter(controller: root).navigateTo(params) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
                XCTAssertFalse(navigation.topViewController === root)
                XCTAssertNil(root.pendingNavigation)
                XCTAssertNotEqual((navigation.topViewController as? MWBWebViewController)?.loadState, .loaded)
                replied.fulfill()
            }
            wait(for: [replied], timeout: 3)
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in navigation.transitionCoordinator == nil }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
        }
    }

    func testNavigateRejectsNonBooleanWaitOption() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let root = MWBWebViewController(configuration: .init(initialURL: url))
        for invalid: Any in ["true", 1, NSNull()] {
            let replied = expectation(description: "strict boolean")
            MWBBridgeAdapter(controller: root).navigateTo(["url": url.absoluteString, "waitForReady": invalid]) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, -1001)
                replied.fulfill()
            }
            wait(for: [replied], timeout: 2)
        }
    }

    func testNavigatePreparationFailureKeepsCurrentPage() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let url = Bundle.main.resourceURL!.appendingPathComponent("mwb-ready-missing.html")
        let replied = expectation(description: "missing local document")
        MWBBridgeAdapter(controller: root).navigateTo(["url": url.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1002)
            XCTAssertTrue(navigation.topViewController === root)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
    }

    func testNavigateRejectsAnotherRequestWhilePreparing() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 500)
        root.host = host
        let first = expectation(description: "first finishes")
        let duplicate = expectation(description: "duplicate rejected")
        let adapter = MWBBridgeAdapter(controller: root)
        adapter.navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0); first.fulfill()
        }
        adapter.navigateTo(["url": root.configuration.initialURL.absoluteString]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1004); duplicate.fulfill()
        }
        wait(for: [duplicate, first], timeout: 5)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertEqual(host.configuredCount, 1)
    }

    func testNavigatePreparationCancelsOnBackgroundAndIgnoresLateLoad() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 500)
        root.host = host
        let started = expectation(description: "real child loading")
        host.configured = { started.fulfill() }
        let replied = expectation(description: "cancelled once")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1005)
            replied.fulfill()
        }
        wait(for: [started], timeout: 2)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        wait(for: [replied], timeout: 2)
        let drained = expectation(description: "late WebKit completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(navigation.viewControllers.count, 1)

        // 任务已在准备时源文档重载，旧 JS 回复必须丢弃，迟到加载不得推动导航。
        let nextStarted = expectation(description: "second target configured")
        host.configured = { nextStarted.fulfill() }
        let oldReply = expectation(description: "invalid source document cannot receive reply")
        oldReply.isInverted = true
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { _, _ in oldReply.fulfill() }
        wait(for: [nextStarted], timeout: 2)
        root.reload()
        wait(for: [oldReply], timeout: 1)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertNil(root.pendingNavigation)
    }

    func testPreparedNavigationTimesOutAndReleasesTarget() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 4500)
        root.host = host
        let replied = expectation(description: "three second timeout")
        let started = Date()
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1002)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 2.9)
            XCTAssertLessThan(Date().timeIntervalSince(started), 4)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertNil(root.pendingNavigation)
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in host.child == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 2), .completed)
    }

    func testPreparedNavigationCancelsWhenSourceLeaves() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 500)
        root.host = host
        let started = expectation(description: "target configured")
        host.configured = { started.fulfill() }
        let replied = expectation(description: "source left")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1005)
            replied.fulfill()
        }
        wait(for: [started], timeout: 2)
        let other = UIViewController()
        navigation.pushViewController(other, animated: false)
        wait(for: [replied], timeout: 2)
        XCTAssertTrue(navigation.topViewController === other)
        XCTAssertNil(root.pendingNavigation)
    }

    func testPreparedNavigationDoesNotReplyToReplacementSourceDocument() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost()
        root.host = host
        let replied = expectation(description: "old reply must be dropped")
        replied.isInverted = true
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { _, _ in replied.fulfill() }
        // 请求尚未在主队列执行时源文档已被替换，同样不能产生导航或回复。
        root.reload()
        wait(for: [replied], timeout: 1)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(host.configuredCount, 0)
        XCTAssertNil(root.pendingNavigation)
    }

    func testPreparedNavigationSurvivesTargetReloadFromHostCallback() throws {
        // 同时覆盖宿主同步重入，以及旧文档快照已在途时的目标文档替换。
        for duringSnapshot in [false, true] {
            let (window, navigation, root) = try readyNavigationContext()
            defer { window.isHidden = true }
            let host = ReadyNavigationHost()
            root.host = host
            host.onLoaded = { [weak host] child in
                if host?.loadedCount == 1 {
                    if duringSnapshot { DispatchQueue.main.async { child.reload() } }
                    else { child.reload() }
                }
            }
            let replied = expectation(description: "replacement target is drawn")
            MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
                XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
                XCTAssertEqual(host.loadedCount, 2)
                XCTAssertEqual((navigation.topViewController as? MWBWebViewController)?.loadState, .loaded)
                replied.fulfill()
            }
            wait(for: [replied], timeout: 5)
        }
    }

    func testPreparedNavigationPresentsLoadedModal() throws {
        let (window, _, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let replied = expectation(description: "prepared popup")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true, "isPopUp": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            let modal = root.presentedViewController as? UINavigationController
            XCTAssertEqual((modal?.topViewController as? MWBWebViewController)?.loadState, .loaded)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
    }

    func testCancelledPreparationDoesNotResumeAfterHostConfigureReentry() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost()
        root.host = host
        var retainedTarget: MWBWebViewController?
        host.configured = {
            retainedTarget = host.child
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }
        let replied = expectation(description: "cancel during host configuration")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, -1005)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 2)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(retainedTarget?.loadState, .idle)
        // 宿主即使保留目标，也不能通过后续 reload 复活已放弃的文档。
        retainedTarget?.reload()
        XCTAssertEqual(retainedTarget?.loadState, .idle)
    }

    func testPreparedNavigationThroughRealJavaScriptBridge() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let started = expectation(description: "JS bridge requested navigation")
        // 用发布 SDK 和真实 DSBridge 通道验证可选参数及成功回复，而非直接调用适配器。
        root.webView?.evaluateJavaScript("""
            window.__readyNavigationResult = null;
            mwb.navigateTo({url: location.href, waitForReady: true})
              .then(result => { window.__readyNavigationResult = result.errCode; })
              .catch(error => { window.__readyNavigationResult = error.errCode; });
            "started";
            """) { _, error in XCTAssertNil(error); started.fulfill() }
        wait(for: [started], timeout: 2)
        let pushed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigation.topViewController !== root && navigation.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pushed], timeout: 5), .completed)
        let child = try XCTUnwrap(navigation.topViewController as? MWBWebViewController)
        XCTAssertEqual(child.loadState, .loaded)
        let replied = expectation(description: "source received bridge success")
        root.webView?.evaluateJavaScript("window.__readyNavigationResult") { value, error in
            XCTAssertNil(error); XCTAssertEqual(value as? Int, 0); replied.fulfill()
        }
        let usable = expectation(description: "target bridge is live")
        child.webView?.evaluateJavaScript("mwb.getDeviceInfoSync().osType") { value, error in
            XCTAssertNil(error); XCTAssertEqual(value as? Int, 2); usable.fulfill()
        }
        wait(for: [replied, usable], timeout: 3)
    }

    func testPreparedNavigationRefreshesViewportChangedDuringLoad() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost(delayMs: 500)
        root.host = host
        let configured = expectation(description: "target begins offscreen load")
        host.configured = { configured.fulfill() }
        let layoutChecked = expectation(description: "offscreen viewport updated before snapshot completes")
        var expectedSize = CGSize.zero
        host.onLoaded = { child in
            DispatchQueue.main.async {
                XCTAssertEqual(child.view.bounds.size, expectedSize)
                XCTAssertTrue(navigation.topViewController === root)
                layoutChecked.fulfill()
            }
        }
        let replied = expectation(description: "resized drawing prepared")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            replied.fulfill()
        }
        wait(for: [configured], timeout: 2)
        // 真实窗口变窄，让 UIKit 重新布局来源，模拟分屏中的可用视口变化。
        window.frame.size.width -= 80
        window.setNeedsLayout(); window.layoutIfNeeded()
        navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded()
        expectedSize = root.view.bounds.size
        XCTAssertNotEqual(expectedSize.width, UIScreen.main.bounds.width)
        wait(for: [layoutChecked, replied], timeout: 5)
    }

    func testPreparedNavigationRepeatsDrawingIfViewportChangesDuringSnapshot() throws {
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        let host = ReadyNavigationHost()
        root.host = host
        var expectedSize = CGSize.zero
        host.onLoaded = { _ in
            // loaded 回调退出后准备器开始异步快照，再改变来源尺寸。
            DispatchQueue.main.async {
                window.frame.size.width -= 70
                window.setNeedsLayout(); window.layoutIfNeeded()
                navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded()
                expectedSize = root.view.bounds.size
            }
        }
        let replied = expectation(description: "current viewport drawing prepared")
        MWBBridgeAdapter(controller: root).navigateTo(["url": root.configuration.initialURL.absoluteString, "waitForReady": true]) { value, _ in
            XCTAssertEqual(MWBResult.parse(value)?.errCode, 0)
            XCTAssertNotEqual(expectedSize, .zero)
            XCTAssertEqual(host.child?.view.bounds.size, expectedSize)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
    }

    // 使用真实Scene与宿主；准备阶段保持源页在原导航栈顶。
    private func readyNavigationContext() throws -> (UIWindow, UINavigationController, MWBWebViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let root = MWBWebViewController(configuration: .init(initialURL: url))
        let navigation = UINavigationController(rootViewController: root)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in root.loadState == .loaded && navigation.transitionCoordinator == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        return (window, navigation, root)
    }

    func testPrewarmingConfigurationDefaultsAndExplicitOptOut() throws {
        // 新增配置默认开启，字符串工厂和导航配置复制均保留显式关闭。
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        XCTAssertTrue(MWBConfiguration(initialURL: url).webViewPrewarmingEnabled)
        XCTAssertTrue(try XCTUnwrap(MWBConfiguration.make(initialURLString: url.absoluteString)).webViewPrewarmingEnabled)
        let disabled = MWBConfiguration(initialURL: url, webViewPrewarmingEnabled: false)
        XCTAssertFalse(disabled.webViewPrewarmingEnabled)
        XCTAssertFalse(try XCTUnwrap(MWBConfiguration.make(initialURLString: url.absoluteString,
            webViewPrewarmingEnabled: false)).webViewPrewarmingEnabled)
        XCTAssertFalse(MWBWebViewController(configuration: disabled).configuration.webViewPrewarmingEnabled)
    }

    func testPrewarmedWebViewTransfersOnlyOnceWithoutInternalHistory() throws {
        // 真实预热实例交给业务后不能返回内部空白页；宿主脚本必须在首文档生效。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        prewarmer.request(from: root)
        waitForWarmSlot(prewarmer)
        let prepared = try XCTUnwrap(prewarmer.takeReady())
        XCTAssertNil(prepared.pluginController)
        let rawBridge = expectation(description: "raw spare has no business bridge")
        prepared.evaluateJavaScript("JSON.parse(prompt('_dsbridge=_dsb.hasNativeMethod',JSON.stringify({data:{name:'mwb.invokePlugin',type:'all'}}))).data") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual((value as? NSNumber)?.boolValue, false)
            rawBridge.fulfill()
        }
        wait(for: [rawBridge], timeout: 5)
        XCTAssertNil(prewarmer.takeReady())
        // 将 ready 实例重新准备的场景由后续真实容器消费覆盖；这里验证原始历史契约。
        let loaded = expectation(description: "prepared local page")
        let delegate = WarmNavigationObserver { loaded.fulfill() }
        prepared.navigationDelegate = delegate
        prepared.loadFileURL(root.configuration.initialURL, allowingReadAccessTo: Bundle.main.resourceURL!)
        wait(for: [loaded], timeout: 10)
        XCTAssertFalse(prepared.canGoBack)
        XCTAssertTrue(prepared.backForwardList.backList.isEmpty)
        let inspected = expectation(description: "raw document history and bridge isolation")
        prepared.evaluateJavaScript("({length:history.length})") { value, error in
            // history 必须和冷路径一样；预热阶段没有注册任何业务 mwb 对象。
            XCTAssertNil(error)
            XCTAssertEqual((value as? [String: Any])?["length"] as? Int, 1)
            inspected.fulfill()
        }
        wait(for: [inspected], timeout: 5)
    }

    func testAutomaticPrewarmingDoesNotRequirePageReadyAndOptOutLeavesSlot() throws {
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        XCTAssertFalse(root.isPageReady)
        waitForWarmSlot(prewarmer)
        let url = root.configuration.initialURL
        let optedOut = MWBWebViewController(configuration: .init(initialURL: url, webViewPrewarmingEnabled: false))
        optedOut.loadViewIfNeeded()
        XCTAssertEqual(prewarmer.state, .ready)
        let host = WarmScriptHost()
        let next = MWBWebViewController(configuration: root.configuration)
        next.host = host
        next.loadViewIfNeeded()
        XCTAssertEqual(prewarmer.state, .empty)
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed)
        XCTAssertEqual(host.configured, 1)
        XCTAssertFalse(next.webView!.canGoBack)
        XCTAssertNotNil(next.pluginSession.identity)
        let script = expectation(description: "host script on real first document")
        next.webView!.evaluateJavaScript("window.webkit.messageHandlers.warmHost.postMessage('real'); window.warmHostScript") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual(value as? String, "configured")
            script.fulfill()
        }
        wait(for: [script], timeout: 5)
        let message = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in host.messages == ["real"] }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [message], timeout: 3), .completed)
        let bridge = expectation(description: "real first document bridge works")
        next.webView!.evaluateJavaScript("window.mwb.getDeviceInfoSync()") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual((value as? [String: Any])?["brand"] as? String, "Apple")
            bridge.fulfill()
        }
        wait(for: [bridge], timeout: 5)
    }

    func testDiscardReleasesSpareAndDoesNotTouchTransferredView() throws {
        // 内存压力只回收备用；已移交业务的实例继续正常工作。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(prewarmer.state, .empty)
        XCTAssertNil(prewarmer.takeReady())
        prewarmer.request(from: root)
        waitForWarmSlot(prewarmer)
        let transferred = try XCTUnwrap(prewarmer.takeReady())
        prewarmer.discard()
        let js = expectation(description: "transferred view is alive")
        transferred.evaluateJavaScript("1 + 1") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual(value as? Int, 2)
            js.fulfill()
        }
        wait(for: [js], timeout: 5)
        XCTAssertEqual(prewarmer.state, .empty)
    }

    func testPrewarmingRefillsAfterAnimatedWarmNavigation() throws {
        // 预热命中后 HTML 通常早于转场结束完成，必须在转场结束后补充备用。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let root = MWBWebViewController(configuration: .init(initialURL: url))
        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        let next = MWBWebViewController(configuration: root.configuration)
        nav.pushViewController(next, animated: true)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            next.loadState == .loaded && nav.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        waitForWarmSlot(prewarmer)
    }

    func testScheduledPrewarmingFollowsLatestVisibleCandidate() throws {
        // 同一个 RunLoop 中 A 消失、B 出现，既有任务应使用最新合格页面。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, first) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        let next = MWBWebViewController(configuration: first.configuration)
        next.loadViewIfNeeded()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        prewarmer.request(from: first)
        XCTAssertEqual(prewarmer.state, .scheduled)
        window.rootViewController = next
        // UIKit 生命周期同步完成，尚未进入 beforeWaiting。
        next.beginAppearanceTransition(true, animated: false)
        next.endAppearanceTransition()
        waitForWarmSlot(prewarmer)
    }

    func testBackgroundAndLateTerminationCannotReviveOrClearNewSlot() throws {
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        let old = try XCTUnwrap(prewarmer.takeReady())
        prewarmer.request(from: root)
        XCTAssertEqual(prewarmer.state, .scheduled)
        XCTAssertNil(prewarmer.takeReady())
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: window.windowScene)
        XCTAssertEqual(prewarmer.state, .empty)
        // 模拟旧实例迟到的终止事件；新代次不能被清空。
        prewarmer.request(from: root)
        waitForWarmSlot(prewarmer)
        prewarmer.webViewWebContentProcessDidTerminate(old)
        XCTAssertEqual(prewarmer.state, .ready)
        let current = try XCTUnwrap(prewarmer.takeReady())
        XCTAssertFalse(current === old)
    }

    func testMemoryWarningDuringWarmingRejectsTakeAndLateCompletion() throws {
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        _ = prewarmer.takeReady()
        prewarmer.request(from: root)
        XCTAssertEqual(prewarmer.state, .scheduled)
        XCTAssertNil(prewarmer.takeReady())
        // 逐步推进 RunLoop，观察真实 WebKit 异步装载中的 warming 阶段。
        let deadline = Date().addingTimeInterval(2)
        while prewarmer.state == .scheduled && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(prewarmer.state, .warming)
        XCTAssertNil(prewarmer.takeReady())
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let drained = expectation(description: "drain late WebKit callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(prewarmer.state, .empty)
    }

    func testSceneActivationRefillsAndHiddenContainerCannotRequest() throws {
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        prewarmer.discard()
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: window.windowScene)
        waitForWarmSlot(prewarmer)
        prewarmer.discard()
        window.isHidden = true
        // 同 Scene 中还有 App 自身窗口；直接验证隐藏候选，避免把其他可见窗口的申请误判为错误。
        prewarmer.request(from: root)
        XCTAssertFalse(root.isEligibleForWebViewPrewarming)
        XCTAssertEqual(prewarmer.state, .empty)
    }

    func testPrewarmingDoesNotRetainClosedBusinessContainer() throws {
        // 备用及空闲候选都不能延长已关闭业务页生命周期。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        weak var released: MWBWebViewController?
        try autoreleasepool {
            let (window, root) = try visiblePrewarmingPage()
            waitForWarmSlot(prewarmer)
            released = root
            window.rootViewController = nil
            window.isHidden = true
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in released == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertEqual(prewarmer.state, .ready)
    }

    func testPrewarmingTimeoutDiscardsAndIgnoresLateFinish() throws {
        // 保留真实 WebKit 工厂，只观察创建的实例，故意阻断完成通知以触发生产 5 秒超时。
        weak var observed: MWBInteractionWebView?
        let prewarmer = MWBWebViewPrewarmer(makeWebView: {
            let webView = MWBInteractionWebView.make()
            observed = webView
            return webView
        })
        let (window, root) = try visiblePrewarmingPage()
        defer { window.isHidden = true; prewarmer.discard(); MWBWebViewPrewarmer.shared.discard() }
        prewarmer.request(from: root)
        let startedAt = Date()
        while prewarmer.state == .scheduled && Date().timeIntervalSince(startedAt) < 2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(prewarmer.state, .warming)
        let spare = try XCTUnwrap(observed)
        spare.navigationDelegate = nil
        XCTAssertNil(prewarmer.takeReady())
        let expired = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in prewarmer.state == .empty }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expired], timeout: 6.5), .completed)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 4.9)
        prewarmer.webView(spare, didFinish: nil)
        XCTAssertEqual(prewarmer.state, .empty)
        XCTAssertNil(prewarmer.takeReady())
    }

    func testInteractivePopFadesVisibleBarAndRestoresOrHidesIt() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let root = MWBWebViewController(configuration: .init(initialURL: url, webViewPrewarmingEnabled: false))
        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.applyNavigationBarPatch(try MWBNavigationBarPatch.parse([:]), hidden: true)
        let child = MWBWebViewController(configuration: root.configuration)
        child.initialNavigationBarHidden = false
        nav.pushViewController(child, animated: false)
        let dark = UIColor(red: 18/255, green: 55/255, blue: 74/255, alpha: 1)
        child.applyNavigationBarPatch(try MWBNavigationBarPatch.parse(["color": "#12374a"]), hidden: false)
        XCTAssertFalse(nav.isNavigationBarHidden)

        // 真实 UIKit 百分比转场暂停在各进度；检查呈现层，避免将动画终值误认为屏幕当前值。
        func waitForTop(_ expected: MWBWebViewController) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                nav.topViewController === expected && nav.transitionCoordinator == nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        }
        let driver = WarmInteractivePopDriver()
        nav.delegate = driver
        nav.popViewController(animated: true)
        var needsCancellation = true
        defer {
            // 即使采样失败，也结束当前交互，避免把暂停的 UIKit 转场留给后续用例。
            if needsCancellation { driver.interaction.cancel(); waitForTop(child) }
            nav.delegate = nil
        }
        func sampleOpacity(at progress: CGFloat, until predicate: (Float) -> Bool) throws -> Float {
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            repeat {
                // 重申同一个手势进度，避免第一次更新早于 UIKit 安装动画时间线。
                driver.interaction.update(progress)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                if let opacity = nav.navigationBar.layer.presentation()?.opacity, predicate(opacity) { return opacity }
            } while ProcessInfo.processInfo.systemUptime < deadline
            return try XCTUnwrap(nil as Float?, "导航栏在手势进度 \(progress) 未呈现预期透明度")
        }
        let early = try sampleOpacity(at: 0.25) { (0.1..<0.99).contains($0) }
        let late = try sampleOpacity(at: 0.75) { $0 < early - 0.05 }
        _ = try sampleOpacity(at: 0.20) { $0 > late + 0.05 }
        XCTAssertFalse(nav.isNavigationBarHidden, "拖动期间不要提前改变导航栏布局")
        XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, dark)

        driver.interaction.cancel()
        needsCancellation = false
        waitForTop(child)
        XCTAssertFalse(nav.isNavigationBarHidden)
        XCTAssertEqual(nav.navigationBar.alpha, 1)
        XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, dark)

        let completing = WarmInteractivePopDriver()
        nav.delegate = completing
        nav.popViewController(animated: true)
        completing.interaction.update(0.75)
        completing.interaction.finish()
        waitForTop(root)
        XCTAssertTrue(nav.isNavigationBarHidden)
        XCTAssertEqual(nav.navigationBar.alpha, 1, "下一次显示导航栏不能继承淡出透明度")
    }

    func testOpaquePushToHiddenBarPreservesSourceAndLayout() throws {
        let (window, nav, root) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        nav.navigationBar.isTranslucent = false
        let source = MWBWebViewController(configuration: root.configuration)
        source.initialNavigationBarHidden = false
        source.title = "来源页"
        nav.pushViewController(source, animated: false)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            source.loadState == .loaded && nav.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        source.applyNavigationBarPatch(try MWBNavigationBarPatch.parse(["color": "#12374a"]), hidden: false)
        window.layoutIfNeeded()
        let sourceColor = UIColor(red: 18/255, green: 55/255, blue: 74/255, alpha: 1)
        let sourceSubviews = source.view.subviews
        let sourceWeb = try XCTUnwrap(source.webView)
        func top(_ view: UIView) -> CGFloat { view.convert(view.bounds, to: window).minY }
        let sourceTop = top(sourceWeb)
        let navTop = top(nav.view)

        // 使用系统默认 push，而不是手动调用生命周期或替换动画控制器。
        let target = PushAppearanceObserver(configuration: root.configuration)
        target.initialNavigationBarHidden = true
        target.configureInitialNavigationBar(try MWBNavigationBarPatch.parse(["color": "#a02030"], strict: true))
        let duringPush = expectation(description: "真实 push 协调器开始动画")
        var targetSafeTop: CGFloat?
        target.onWillAppear = {
            guard let transition = target.transitionCoordinator else {
                XCTFail("默认动画 push 应有真实转场协调器")
                duringPush.fulfill()
                return
            }
            XCTAssertTrue(transition.isAnimated)
            XCTAssertFalse(transition.isInteractive)
            XCTAssertTrue(transition.viewController(forKey: .from) === source)
            XCTAssertTrue(nav.isNavigationBarHidden, "目标页不能为真实栏预留位置")
            guard let overlay = source.view.subviews.first(where: { !sourceSubviews.contains($0) }) else {
                XCTFail("真实栏隐藏时来源页仍可见，必须保留它的导航栏快照")
                duringPush.fulfill()
                return
            }
            XCTAssertTrue(transition.animate(alongsideTransition: { _ in
                XCTAssertFalse(overlay.isUserInteractionEnabled)
                XCTAssertTrue(overlay.accessibilityElementsHidden)
                XCTAssertEqual(overlay.alpha, 1)
                XCTAssertEqual(overlay.subviews.first?.backgroundColor, sourceColor, "不能提前换成目标页的颜色")
                XCTAssertEqual(top(overlay), navTop, accuracy: 1, "应覆盖状态栏背后的区域")
                XCTAssertEqual(top(sourceWeb), sourceTop, accuracy: 1, "来源内容不应突然上移")
                if let targetWeb = target.webView {
                    XCTAssertEqual(top(targetWeb), navTop, accuracy: 1)
                    targetSafeTop = targetWeb.safeAreaInsets.top
                }
                duringPush.fulfill()
            }))
        }
        defer { target.onWillAppear = nil }
        nav.pushViewController(target, animated: true)
        wait(for: [duringPush], timeout: 5)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            nav.topViewController === target && nav.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        XCTAssertTrue(nav.isNavigationBarHidden)
        XCTAssertEqual(source.view.subviews, sourceSubviews, "动画结束后应移除临时快照")
        XCTAssertNotNil(targetSafeTop, "需要测到真正转场中的目标页安全区")
        if let targetSafeTop {
            XCTAssertEqual(try XCTUnwrap(target.webView).safeAreaInsets.top,
                           targetSafeTop, accuracy: 1, "目标顶部安全区在动画结束后不能跳动")
        }
        XCTAssertTrue(nav.popViewController(animated: true) === target)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            nav.topViewController === source && nav.transitionCoordinator == nil && !nav.isNavigationBarHidden
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, sourceColor)
    }

    func testOpaqueInteractivePopKeepsDestinationGeometryAndRestoresSourceOnCancel() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "navigation-theme", withExtension: "html"))
        let target = MWBWebViewController(configuration: .init(initialURL: url, webViewPrewarmingEnabled: false))
        let nav = UINavigationController(rootViewController: target)
        nav.navigationBar.isTranslucent = false
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        target.applyNavigationBarPatch(try MWBNavigationBarPatch.parse([:]), hidden: true)
        window.layoutIfNeeded()
        let targetWeb = try XCTUnwrap(target.webView)
        func top(_ view: UIView) -> CGFloat { view.convert(.zero, to: nav.view).y }
        func safeTop(_ view: UIView) -> CGFloat { top(view) + view.safeAreaInsets.top }
        let targetTop = top(targetWeb)
        let targetSafeTop = safeTop(targetWeb)

        let source = MWBWebViewController(configuration: target.configuration)
        source.initialNavigationBarHidden = false
        nav.pushViewController(source, animated: false)
        // 初始 H5 会刷新页面级按钮，等它加载完再配置待验证的来源样式。
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.loadState == .loaded && source.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)

        source.applyNavigationBarPatch(try MWBNavigationBarPatch.parse([
            "color": "#12374a", "title": "任务库", "buttonColor": "#ffffff", "backButtonStyle": "arrowText"
        ]), hidden: false)
        source.configureNavigationAction(title: "新建任务", ext: "add")
        window.layoutIfNeeded()
        let sourceWeb = try XCTUnwrap(source.webView)
        let sourceTop = top(sourceWeb)
        let sourceColor = nav.navigationBar.standardAppearance.backgroundColor
        let barTop = top(nav.navigationBar)
        let navigationTop = nav.view.bounds.minY
        XCTAssertGreaterThan(barTop, navigationTop, "测试设备的导航栏上方应有可见的状态栏区域")
        let sourceButtonColor = nav.navigationBar.tintColor
        let actionItem = try XCTUnwrap(source.navigationItem.rightBarButtonItem)
        let sourceSubviews = source.view.subviews.count
        XCTAssertGreaterThan(sourceTop, targetTop, "不透明栏下的来源页应实际占据不同的布局")

        func waitForTop(_ expected: MWBWebViewController) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                nav.topViewController === expected && nav.transitionCoordinator == nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        }
        for attempt in 0..<3 {
            let driver = WarmInteractivePopDriver()
            nav.delegate = driver
            nav.popViewController(animated: true)
            // UIKit 可能在第一次 update 后才安装动画时间线；按进度采样真实的呈现层。
            for progress: CGFloat in attempt == 0 ? [0.25, 0.75, 0.2] : [0.55] {
                let deadline = ProcessInfo.processInfo.systemUptime + 2
                let width = nav.view.bounds.width
                var visibleX: CGFloat = 0
                repeat {
                    driver.interaction.update(progress)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    visibleX = source.view.layer.presentation()?.transform.m41 ?? 0
                    if abs(visibleX - width * progress) < width * 0.15 { break }
                } while ProcessInfo.processInfo.systemUptime < deadline
                XCTAssertLessThan(abs(visibleX - width * progress), width * 0.15, "来源页应移动到手势进度")
                XCTAssertTrue(nav.isNavigationBarHidden, "真实栏不能继续占据目标页顶部")
                XCTAssertEqual(top(targetWeb), targetTop, accuracy: 1, "目标 WebView 拖动中不应下移")
                XCTAssertEqual(safeTop(targetWeb), targetSafeTop, accuracy: 1, "目标顶部安全区应与静止时一致")
                XCTAssertEqual(top(sourceWeb), sourceTop, accuracy: 1, "来源 H5 不应在快照下突然上移")
                let overlay = source.view.subviews.count > sourceSubviews ? source.view.subviews.last : nil
                XCTAssertEqual(source.view.subviews.count, sourceSubviews + 1)
                XCTAssertEqual(overlay?.isUserInteractionEnabled, false)
                XCTAssertEqual(overlay?.isAccessibilityElement, false)
                XCTAssertEqual(overlay?.accessibilityElementsHidden, true)
                // 状态栏背景必须和标题栏在同一个退场视图内，且不改变目标页布局。
                let backdrop = overlay?.subviews.first
                XCTAssertEqual(backdrop?.backgroundColor, sourceColor, "侧滑时保留来源页的状态栏底色")
                XCTAssertEqual(backdrop.map(top) ?? .infinity, navigationTop, accuracy: 1)
                XCTAssertEqual(backdrop?.bounds.height ?? 0, barTop - navigationTop, accuracy: 1)
                // 栏和状态栏底色整体保持不透明，避免拖动或反拖时透出黑色转场底。
                let opacity = overlay?.layer.presentation()?.opacity ?? -1
                XCTAssertEqual(opacity, 1, accuracy: 0.001, "手势进度 \(progress) 时应保持原色")
            }
            if attempt < 2 {
                // 目标页主题更新必须缓存，不能在拖动中重新显示共享栏。
                if attempt == 0 {
                    target.applyNavigationBarPatch(try MWBNavigationBarPatch.parse(["color": "#3c5350"]), hidden: false)
                    XCTAssertTrue(nav.isNavigationBarHidden)
                    target.applyNavigationBarPatch(try MWBNavigationBarPatch.parse([:]), hidden: true)
                }
                driver.interaction.cancel()
                waitForTop(source)
                XCTAssertFalse(nav.isNavigationBarHidden)
                XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, sourceColor)
                XCTAssertEqual(nav.navigationBar.tintColor, sourceButtonColor)
                XCTAssertEqual(nav.navigationBar.alpha, 1)
                XCTAssertTrue(source.navigationItem.rightBarButtonItem === actionItem)
                let backButton = try XCTUnwrap(source.navigationItem.leftBarButtonItem?.customView as? UIButton)
                XCTAssertEqual(backButton.accessibilityLabel, "返回")
                XCTAssertTrue(backButton.isEnabled)
            } else {
                driver.interaction.finish()
                waitForTop(target)
                XCTAssertTrue(nav.isNavigationBarHidden)
                XCTAssertEqual(safeTop(targetWeb), targetSafeTop, accuracy: 1)
            }
            XCTAssertFalse(nav.navigationBar.isTranslucent)
            XCTAssertEqual(source.view.subviews.count, sourceSubviews, "每次转场都应移除自己的快照")
        }
    }

    func testInteractivePopRevealsDestinationBarWithPage() throws {
        try assertInteractivePopLayout(translucent: false)
    }

    func testInteractivePopPreservesTranslucentPageContentPosition() throws {
        // Demo 默认使用半透明系统栏；同样验证拖动、回拖、取消和完成。
        try assertInteractivePopLayout(translucent: true)
    }

    private func assertInteractivePopLayout(translucent: Bool) throws {
        let (window, nav, root) = try readyNavigationContext()
        defer { window.isHidden = true; MWBWebViewPrewarmer.shared.discard() }
        nav.navigationBar.isTranslucent = translucent
        let target = MWBWebViewController(configuration: root.configuration)
        // 使用录屏中的 H5 页面，它直接读取 CSS env(safe-area-inset-top)。
        target.initialPageOverride = root.configuration.initialURL.deletingLastPathComponent().appendingPathComponent("navigation-theme.html")
        target.initialNavigationBarHidden = false
        nav.pushViewController(target, animated: false)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.loadState == .loaded && nav.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        try target.applyNavigationBarPatch(MWBNavigationBarPatch.parse([
            "color": "#12374a", "title": "返回目标", "backButtonStyle": "arrowText"
        ]), hidden: false)
        window.layoutIfNeeded()
        let targetWeb = try XCTUnwrap(target.webView)
        let targetSubviews = target.view.subviews
        let color = nav.navigationBar.standardAppearance.backgroundColor
        func top(_ view: UIView) -> CGFloat { view.convert(view.bounds, to: window).minY }
        let targetTop = top(targetWeb)
        let targetSafeTop = targetWeb.safeAreaInsets.top
        // 屏幕上的正文原点还取决于滚动偏移，而不只是 WebView 的外框。
        func contentTop() -> CGFloat { targetWeb.scrollView.convert(.zero, to: window).y }
        func firstRowTop() throws -> CGFloat {
            let done = expectation(description: "读取页面首行实际位置")
            var result: NSNumber?
            targetWeb.evaluateJavaScript("document.querySelector('.theme-page-top').getBoundingClientRect().top") { value, error in
                XCTAssertNil(error); result = value as? NSNumber; done.fulfill()
            }
            wait(for: [done], timeout: 3)
            return CGFloat(try XCTUnwrap(result).doubleValue)
        }
        let restingContentTop = contentTop()
        let restingRowTop = try firstRowTop()
        let barTop = top(nav.navigationBar)
        let navTop = top(nav.view)
        XCTAssertGreaterThan(barTop, navTop)

        func waitForTop(_ expected: UIViewController) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                nav.topViewController === expected && nav.transitionCoordinator == nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        }
        let source = MWBWebViewController(configuration: target.configuration)
        source.initialNavigationBarHidden = true
        nav.pushViewController(source, animated: true)
        waitForTop(source)
        XCTAssertTrue(nav.isNavigationBarHidden)
        let sourceWeb = try XCTUnwrap(source.webView)
        let sourceTop = top(sourceWeb)
        let sourceSafeTop = sourceWeb.safeAreaInsets.top
        let width = window.bounds.width

        for completes in [false, true] {
            let driver = WarmInteractivePopDriver(destinationParallax: true)
            nav.delegate = driver
            nav.popViewController(animated: true)
            var needsCancellation = true
            defer {
                if needsCancellation { driver.interaction.cancel(); waitForTop(source) }
                nav.delegate = nil
            }
            for progress in [CGFloat(0.2), 0.7, 0.25] {
                let deadline = ProcessInfo.processInfo.systemUptime + 2
                repeat {
                    driver.interaction.update(progress)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    let sourceX = source.view.layer.presentation()?.transform.m41 ?? 0
                    if abs(sourceX - width * progress) < width * 0.13 { break }
                } while ProcessInfo.processInfo.systemUptime < deadline
                let sourceX = source.view.layer.presentation()?.transform.m41 ?? 0
                XCTAssertEqual(sourceX, width * progress, accuracy: width * 0.13)
                XCTAssertEqual(nav.navigationBar.layer.presentation()?.opacity ?? 1, 0, accuracy: 0.001,
                               "共享栏不能盖住尚未滑走的无栏页")
                let overlay = try XCTUnwrap(target.view.subviews.first(where: { !targetSubviews.contains($0) }),
                                            "导航栏应随目标页露出，而不是铺在两页上方")
                XCTAssertEqual(overlay.subviews.first?.backgroundColor, color)
                XCTAssertEqual(top(overlay), navTop, accuracy: 1)
                XCTAssertFalse(overlay.isUserInteractionEnabled)
                XCTAssertTrue(overlay.accessibilityElementsHidden)
                XCTAssertEqual(top(sourceWeb), sourceTop, accuracy: 1)
                XCTAssertEqual(sourceWeb.safeAreaInsets.top, sourceSafeTop, accuracy: 1)
                XCTAssertEqual(try firstRowTop(), restingRowTop, accuracy: 1)
                XCTAssertEqual(contentTop(), restingContentTop, accuracy: 1)
                XCTAssertEqual(top(targetWeb), targetTop, accuracy: 1)
                XCTAssertEqual(targetWeb.safeAreaInsets.top, targetSafeTop, accuracy: 1)
            }
            if completes { driver.interaction.finish() } else { driver.interaction.cancel() }
            needsCancellation = false
            waitForTop(completes ? target : source)
            XCTAssertEqual(nav.isNavigationBarHidden, !completes)
            XCTAssertEqual(nav.navigationBar.alpha, 1)
            XCTAssertEqual(target.view.subviews, targetSubviews, "转场收尾应清理临时导航栏")
            if completes {
                XCTAssertEqual(try firstRowTop(), restingRowTop, accuracy: 1)
                XCTAssertEqual(contentTop(), restingContentTop, accuracy: 1)
                XCTAssertEqual(top(targetWeb), targetTop, accuracy: 1)
                XCTAssertEqual(targetWeb.safeAreaInsets.top, targetSafeTop, accuracy: 1)
                XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, color)
                XCTAssertEqual(target.navigationItem.leftBarButtonItem?.customView?.accessibilityLabel, "返回")
            } else {
                XCTAssertEqual(top(sourceWeb), sourceTop, accuracy: 1)
                XCTAssertEqual(sourceWeb.safeAreaInsets.top, sourceSafeTop, accuracy: 1)
            }
        }
    }

    func testCancelledInteractivePopRestoresPrewarmingEligibility() throws {
        // 用 UIKit 真实百分比转场触发取消生命周期，不手工调用 didAppear 来替代取消。
        let prewarmer = MWBWebViewPrewarmer.shared
        prewarmer.discard()
        defer { prewarmer.discard() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let root = MWBWebViewController(configuration: .init(initialURL: url))
        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        waitForWarmSlot(prewarmer)
        let next = MWBWebViewController(configuration: root.configuration)
        nav.pushViewController(next, animated: false)
        waitForWarmSlot(prewarmer)
        prewarmer.discard()
        let driver = WarmInteractivePopDriver()
        nav.delegate = driver
        nav.popViewController(animated: true)
        driver.interaction.update(0.3)
        XCTAssertFalse(next.isEligibleForWebViewPrewarming)
        driver.interaction.cancel()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            nav.topViewController === next && nav.transitionCoordinator == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 5), .completed)
        XCTAssertTrue(next.isEligibleForWebViewPrewarming)
        waitForWarmSlot(prewarmer)
        nav.delegate = nil
    }

    // 测试保留真实 Scene 与 WebKit 生命周期，不通过生产测试开关注入 ready 状态。
    private func visiblePrewarmingPage() throws -> (UIWindow, MWBWebViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        return (window, controller)
    }

    private func waitForWarmSlot(_ prewarmer: MWBWebViewPrewarmer) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in prewarmer.state == .ready }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

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

// 宿主仅在真实容器配置时安装脚本，预热不得提前调用这个钩子。
private final class WarmScriptHost: NSObject, MWBHostDelegate, WKScriptMessageHandler {
    var configured = 0
    var messages: [String] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message.body as? String ?? "")
    }
    func configureContainer(_ container: MWBWebViewController) {
        configured += 1
        container.webView?.configuration.userContentController.add(self, name: "warmHost")
        container.webView?.configuration.userContentController.addUserScript(WKUserScript(
            source: "window.warmHostScript = 'configured'", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
}

private final class WarmNavigationObserver: NSObject, WKNavigationDelegate {
    let finished: () -> Void
    init(_ finished: @escaping () -> Void) { self.finished = finished }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
}

// 在 UIKit 调用真实生命周期时采样，不依赖模拟器转场速度或固定等待时长。
private final class PushAppearanceObserver: MWBWebViewController {
    var onWillAppear: (() -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onWillAppear?()
    }
}

// 测试使用 UIKit 真正的交互转场协调器，覆盖取消后 controller 的外观生命周期。
private final class WarmInteractivePopDriver: NSObject, UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning {
    let interaction = UIPercentDrivenInteractiveTransition()
    private let destinationParallax: Bool
    init(destinationParallax: Bool = false) { self.destinationParallax = destinationParallax }
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        operation == .pop ? self : nil
    }
    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.25 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let from = context.view(forKey: .from)!
        let to = context.view(forKey: .to)!
        context.containerView.insertSubview(to, belowSubview: from)
        let width = context.containerView.bounds.width
        // 模拟系统手势中的目标页视差，验证顶部展示跟随同一个视图。
        if destinationParallax { to.transform = CGAffineTransform(translationX: -width * 0.3, y: 0) }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            from.transform = CGAffineTransform(translationX: width, y: 0)
            to.transform = .identity
        }, completion: { _ in
            from.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        })
    }
}

// 可控的真实页面执行时间用于覆盖准备与取消，不向生产代码增加测试状态开关。
private final class ReadyNavigationHost: MWBHostDelegate {
    let delayMs: Int
    var configuredCount = 0
    var loadedCount = 0
    var configured: (() -> Void)?
    var onLoaded: ((MWBWebViewController) -> Void)?
    weak var child: MWBWebViewController?
    init(delayMs: Int = 0) { self.delayMs = delayMs }
    func configureContainer(_ container: MWBWebViewController) {
        child = container
        configuredCount += 1
        container.onLoadStateChange = { [weak self, weak container] state in
            if state == .loaded, let self, let container {
                self.loadedCount += 1
                self.onLoaded?(container)
            }
        }
        if delayMs > 0 {
            container.webView?.configuration.userContentController.addUserScript(WKUserScript(
                source: "{const until=Date.now()+\(delayMs);while(Date.now()<until){}}",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        configured?()
    }
}
