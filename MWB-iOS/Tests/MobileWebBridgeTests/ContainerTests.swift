import XCTest
import WebKit
import Network
@testable import MobileWebBridge

final class ContainerTests: XCTestCase {
    func testControllerUsesConfiguredInitialURL() {
        let url = URL(string: "https://example.com/app")!
        let configuration = MWBConfiguration(initialURL: url, allowedOrigins: ["https://example.com"])
        let controller = MWBWebViewController(configuration: configuration)

        XCTAssertEqual(controller.configuration.initialURL, url)
        XCTAssertEqual(controller.loadState, .idle)
    }

    func testConfigurationRejectsEmptyURL() {
        XCTAssertNil(MWBConfiguration.make(initialURLString: "", allowedOrigins: []))
    }

    func testReadyIsIndependentIdempotentAndResetByReload() {
        // 使用真实主文档身份，让通知经过生产网关。
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = ObservedWebController(configuration: .init(initialURL: url, allowedOrigins: []))
        var states: [MWBLoadState] = []
        var readyCount = 0
        controller.onLoadStateChange = { states.append($0); XCTAssertTrue(Thread.isMainThread) }
        controller.onPageReady = { readyCount += 1; XCTAssertTrue(Thread.isMainThread) }
        controller.loadViewIfNeeded()
        XCTAssertEqual(states.first, .loading)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.loadState == .loaded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        let document = controller.pluginSession.identity!
        let request: [String: Any] = ["protocol": 1, "documentId": document,
            "plugin": "basic", "method": "notifyPageReady", "params": NSNull(), "callId": "ready"]
        XCTAssertFalse(controller.isPageReady)
        controller.pluginSession.invoke(request) { XCTAssertEqual($0.errCode, 0) }
        controller.pluginSession.invoke(request) { XCTAssertEqual($0.errCode, 0) }
        XCTAssertEqual(readyCount, 1)
        XCTAssertEqual(controller.overrideCount, 1)
        XCTAssertTrue(controller.isPageReady)
        controller.reload()
        XCTAssertEqual(controller.loadState, .loading)
        XCTAssertFalse(controller.isPageReady)
        controller.pluginSession.invoke(request) { XCTAssertNotEqual($0.errCode, 0) }
        XCTAssertEqual(readyCount, 1)
    }
    func testHTTPMainFrameFailureDoesNotReportLoaded() throws {
        // WebKit 响应不可安全手动构造；使用回环地址和系统分配端口返回真实 503。
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let listening = expectation(description: "loopback listener ready")
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let response = Data("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        wait(for: [listening], timeout: 5)
        let origin = "http://127.0.0.1:\(try XCTUnwrap(listener.port).rawValue)"
        let controller = MWBWebViewController(configuration: .init(
            initialURL: URL(string: origin + "/")!, allowedOrigins: [origin]))
        let failed = expectation(description: "HTTP failure reported")
        controller.onLoadStateChange = { state in if case .failed = state { failed.fulfill() } }
        controller.loadViewIfNeeded()
        wait(for: [failed], timeout: 10)
        XCTAssertEqual(controller.loadState, .failed("HTTP 503"))
        XCTAssertFalse(controller.isPageReady)
    }

    func testOverrideCanReloadAndSuppressOldDocumentClosure() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        let controller = ObservedWebController(configuration: .init(initialURL: url, allowedOrigins: []))
        controller.loadViewIfNeeded()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.loadState == .loaded }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        var closureCalls = 0
        controller.onPageReady = { closureCalls += 1 }
        controller.overrideAction = { [weak controller] in controller?.reload() }
        let document = controller.pluginSession.identity!
        controller.pluginSession.invoke(["protocol": 1, "documentId": document,
            "plugin": "basic", "method": "notifyPageReady", "callId": "reentrant"]) { _ in }
        XCTAssertEqual(controller.overrideCount, 1)
        XCTAssertEqual(closureCalls, 0)
        XCTAssertFalse(controller.isPageReady)
        XCTAssertEqual(controller.loadState, .loading)
    }

}

/// 不调用 super 也不能跳过库内部的就绪状态与去重。
private final class ObservedWebController: MWBWebViewController {
    var overrideCount = 0
    var overrideAction: (() -> Void)?
    override func pageDidBecomeReady() {
        XCTAssertTrue(isPageReady)
        overrideCount += 1
        overrideAction?()
    }
}
