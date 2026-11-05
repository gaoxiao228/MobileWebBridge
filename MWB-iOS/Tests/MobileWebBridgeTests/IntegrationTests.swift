import XCTest
import WebKit
@testable import MobileWebBridge
@testable import MWBExample

final class IntegrationTests: XCTestCase {
    func testNativeExampleHandlesExplicitPageReadyNotifications() throws {
        // H5 Demo 不自动报告；测试通过真实 SDK 主动通知，验证原生示例仍可接入业务页面。
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let controller = ExampleWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        var callbacks = 0
        controller.onPageReady = { callbacks += 1 }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func waitUntilLoaded() {
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.loadState == .loaded }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
            XCTAssertFalse(controller.isPageReady)
        }
        func notifyReady() {
            let notified = expectation(description: "explicit readiness notification")
            controller.webView?.callAsyncJavaScript("""
                await mwb.basic.notifyPageReady();
                return true;
                """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): XCTAssertEqual(value as? Bool, true)
                case .failure(let error): XCTFail(error.localizedDescription)
                }
                notified.fulfill()
            }
            wait(for: [notified], timeout: 10)
            XCTAssertTrue(controller.isPageReady)
        }
        waitUntilLoaded()
        XCTAssertEqual(callbacks, 0)
        notifyReady()
        notifyReady()
        XCTAssertEqual(callbacks, 1)
        controller.reload()
        XCTAssertFalse(controller.isPageReady)
        waitUntilLoaded()
        notifyReady()
        XCTAssertEqual(callbacks, 2)
    }

    func testBundledPageCallsNativeAppInfoThroughDSBridge() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let host = DemoHost()
        controller.host = host
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)

        let result = expectation(description: "JS receives native app info")
        controller.webView?.evaluateJavaScript("mwb.getAppInfoSync().appId") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual(value as? String, "mwb-integration-test")
            result.fulfill()
        }
        wait(for: [result], timeout: 10)
    }

    func testNativeCanCallRegisteredJavaScriptHandler() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)

        let registered = expectation(description: "JS handler registered")
        controller.webView?.evaluateJavaScript(
            "dsBridge.register('mwb.echo', function(value) { return value + '!'; })"
        ) { _, error in
            XCTAssertNil(error)
            registered.fulfill()
        }
        wait(for: [registered], timeout: 5)

        let invoked = expectation(description: "native receives JS result")
        controller.callJSHandler("echo", arguments: ["hello"]) { value in
            XCTAssertEqual(value as? String, "hello!")
            invoked.fulfill()
        }
        wait(for: [invoked], timeout: 5)
    }

    func testNavigationTextButtonInvokesJavaScriptCallback() throws {
        // 验证从 SDK 设置文字按钮，到原生点击，再回到当前 H5 回调的完整链路。
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html"))
        let controller = MWBWebViewController(configuration: .init(initialURL: url, allowedOrigins: []))
        controller.loadViewIfNeeded()
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)

        let configured = expectation(description: "JS configured native text button")
        controller.webView?.callAsyncJavaScript("""
            window.__mwbActionClick = null;
            await mwb.setNavigationBarTheme({
              actionTxt: '保存', actionExt: 'draft-42',
              onActionClick: data => { window.__mwbActionClick = data.actionExt; }
            });
            return true;
            """, arguments: [:], in: nil, in: .page) { result in
            if case let .failure(error) = result { XCTFail(error.localizedDescription) }
            configured.fulfill()
        }
        wait(for: [configured], timeout: 10)
        let button = try XCTUnwrap(controller.navigationItem.rightBarButtonItem)
        XCTAssertEqual(button.title, "保存")
        _ = button.target?.perform(button.action)

        let clicked = expectation(description: "JS callback receives actionExt")
        func checkClick() {
            controller.webView?.evaluateJavaScript("window.__mwbActionClick") { value, _ in
                if value as? String == "draft-42" { clicked.fulfill() }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: checkClick) }
            }
        }
        checkClick()
        wait(for: [clicked], timeout: 5)
    }
}

// 测试宿主只提供应用信息，验证桥接结果来自 Swift 而非网页常量。
private final class DemoHost: MWBHostDelegate {
    func appInfo() -> [String: Any]? {
        ["appId": "mwb-integration-test", "appVersionName": "1.0", "appVersionCode": 1, "environment": 0]
    }
}
