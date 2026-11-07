import XCTest
import UIKit
import WebKit
@testable import MobileWebBridge

final class NavigationTests: XCTestCase {
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
        let (window, navigation, root) = try readyNavigationContext()
        defer { window.isHidden = true }
        // 目标故意不存在：无需依赖 WebKit 与 UIKit 的竞争时序，即可证明默认路径不等待加载成功。
        let missingURL = Bundle.main.resourceURL!.appendingPathComponent("mwb-immediate-missing.html")
        for option in [false, true] {
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
            navigation.popToRootViewController(animated: false)
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

// 测试使用 UIKit 真正的交互转场协调器，覆盖取消后 controller 的外观生命周期。
private final class WarmInteractivePopDriver: NSObject, UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning {
    let interaction = UIPercentDrivenInteractiveTransition()
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
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            from.transform = CGAffineTransform(translationX: context.containerView.bounds.width, y: 0)
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
