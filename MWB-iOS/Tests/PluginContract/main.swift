import Foundation
import JavaScriptCore

// 假服务只替代外网，参数验证、网关、响应和事件仍执行生产代码。
final class FakeNetworkService: ExampleNetworkServing {
    var requests: [URLRequest] = []
    var callbacks: [(Result<ExampleNetworkResponse, Error>) -> Void] = []
    var cancelled = 0
    func send(_ request: URLRequest, completion: @escaping (Result<ExampleNetworkResponse, Error>) -> Void) -> () -> Void {
        requests.append(request); callbacks.append(completion)
        return { self.cancelled += 1 }
    }
}

// macOS 原生检查只替代 UIKit 类型；插件、注册表及会话使用真实生产代码。
public class MWBWebViewController: NSObject {}
private var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fatalError("FAIL: \(message)") }
}
func pump(_ seconds: TimeInterval = 0.02) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
final class EchoPlugin: MWBPlugin {
    var disposed = false
    var late: MWBPluginResponder?
    var savedContext: MWBPluginCallContext?
    var cancelled = 0
    @objc(mwb_echo:context:responder:)
    func echo(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        savedContext = context
        responder.success(params)
        responder.failure(-1, message: "duplicate")
    }
    @objc(mwb_wait:context:responder:)
    func wait(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        savedContext = context
        late = responder
        context.onCancel { self.cancelled += 1 }
    }
    @objc(mwb_badJSON:context:responder:)
    func badJSON(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        responder.success(Double.nan)
    }
    @objc(mwb_race:context:responder:)
    func race(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: 16) { _ in responder.success("worker") }
        }
    }
    override func dispose() { disposed = true }
    @objc func helper() {}
}
final class BadPlugin: MWBPlugin {
    @objc(mwb_bad:context:responder:)
    func bad(_ p: Int, context: MWBPluginCallContext, responder: MWBPluginResponder) {}
}
final class BadReturnPlugin: MWBPlugin {
    @objc(mwb_bad:context:responder:)
    func bad(_ p: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) -> Int { 1 }
}
final class BadCountPlugin: MWBPlugin {
    @objc(mwb_bad:context:)
    func bad(_ p: Any?, context: MWBPluginCallContext) {}
}
final class ExceptionPlugin: MWBPlugin {
    @objc(mwb_raise:context:responder:)
    func raise(_ p: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        NSException(name: .invalidArgumentException, reason: "fixture").raise()
    }
}
let network = FakeNetworkService()
let slowPlugin = EchoPlugin()
let reentrantPlugin = EchoPlugin()
var factoryNavigation: (() -> Void)?
let registry = MWBPluginRegistry()
var created = 0
var instances: [EchoPlugin] = []
try registry.register(name: "echo") {
    created += 1
    let plugin = EchoPlugin(); instances.append(plugin); return plugin
}
for name in ["basic", "then", "getStorageSync", "onPageShow", "dispatchEvent", "backBtnPressed", "pluginSession", "Bad", "foo-bar"] {
    do { try registry.register(name: name) { EchoPlugin() }; fatalError("reserved name accepted: \(name)") }
    catch {}
}
do { try registry.register(name: "echo") { EchoPlugin() }; fatalError("duplicate accepted") } catch {}
try registry.register(name: "broken") { BadPlugin() }
try registry.register(name: "badReturn") { BadReturnPlugin() }
try registry.register(name: "badCount") { BadCountPlugin() }
try registry.register(name: "exception") { ExceptionPlugin() }
try registry.register(name: "factoryError") { throw MWBPluginConfigurationError.invalidSignature }
try registry.register(name: "reentrant") { factoryNavigation?(); return reentrantPlugin }
try registry.register(name: "slow") { Thread.sleep(forTimeInterval: 0.03); return slowPlugin }
try registry.register(name: "network") { ExampleNetworkPlugin(service: network) }
let snapshot = registry.snapshot()
do { try registry.register(name: "later") { EchoPlugin() }; fatalError("late registration accepted") } catch {}
var trusted = true
var events: [[String: Any]] = []
let url = URL(string: "https://example.com/one")!
let session = MWBPluginSession(snapshot: snapshot, controller: nil,
    trustedURL: { trusted ? url : nil }, event: { events.append($0) })
session.beginDocument(url: url)
let handshake = session.handshake()
check(handshake.errCode == 0, "initial document immediately available")
let doc = (handshake.result as! [String: Any])["documentId"] as! String
func args(_ method: String, id: String = UUID().uuidString, timeout: Int = 30000,
          plugin: String = "echo", document: String = doc, params: Any = NSNull()) -> [String: Any] {
    ["protocol": 1, "documentId": document, "plugin": plugin, "method": method,
     "params": params, "callId": id, "timeoutMs": timeout]
}
check((session.info(["protocol": 1, "documentId": doc, "plugin": "echo"]).result as? [String: Bool])?["available"] == true,
      "info reports registered plugin")
check(created == 0, "info does not create instance")
func invoke(_ p: [String: Any]) -> [MWBResult] {
    var out: [MWBResult] = []
    session.invoke(p) { out.append($0) }; pump(); return out
}
check(invoke(args("bad", plugin: "badReturn"))[0].errCode == -1105, "non void return rejected")
check(invoke(args("bad", plugin: "badCount"))[0].errCode == -1105, "wrong argument count rejected")
check(invoke(args("echo", plugin: "factoryError"))[0].errCode == -1105, "throwing factory rejected")
check(invoke(args("raise", plugin: "exception"))[0].errCode == -1105, "Objective-C exception converted")
check(invoke(args("echo", timeout: 1, plugin: "slow"))[0].errCode == -1103,
      "timeout includes factory initialization")
check(slowPlugin.savedContext == nil, "expired factory does not enter business method")
let echo = invoke(args("echo", params: NSNull()))
check(echo.count == 1 && echo[0].errCode == 0 && echo[0].result is NSNull, "explicit null and one completion")
let raced = invoke(args("race"))
check(raced.count == 1 && raced[0].result as? String == "worker", "background concurrent responders complete once")
check(invoke(args("helper"))[0].errCode == -1101, "unmarked method hidden")
check(invoke(args("description"))[0].errCode == -1101, "NSObject member hidden")
check(invoke(args("bad", plugin: "broken"))[0].errCode == -1105, "invalid ABI rejected before invocation")
check(invoke(args("echo", plugin: "missing"))[0].errCode == -1100, "missing plugin")
check(invoke(args("badJSON"))[0].errCode == -1102, "invalid result rejected")
check(invoke(args("echo", document: "stale"))[0].errCode == -1104, "stale document")
var protocolArgs = args("echo"); protocolArgs["protocol"] = 2
check(invoke(protocolArgs)[0].errCode == -1106, "protocol mismatch")
var invalid = args("echo"); invalid["params"] = Date()
check(invoke(invalid)[0].errCode == -1102, "non JSON params")
check(invoke(args("echo", timeout: 0))[0].errCode == -1102, "invalid timeout")
var timed: [MWBResult] = []
session.invoke(args("wait", timeout: 1)) { timed.append($0) }; pump()
check(timed.count == 1 && timed[0].errCode == -1103, "timeout completes once")
check(instances[0].cancelled == 1, "timeout cancels host work")
instances[0].late?.success("late"); pump()
check(timed.count == 1, "late timeout result dropped")
instances[0].savedContext?.emit("finished", data: ["value": 1]); pump()
check(events.count == 1 && events[0]["documentId"] as? String == doc && events[0]["plugin"] as? String == "echo", "event identity")
instances[0].savedContext?.emit("then", data: 1); pump()
check(events.count == 1, "reserved event blocked")
var pending: [MWBResult] = []
session.invoke(args("wait", id: "same")) { pending.append($0) }; pump()
check(invoke(args("wait", id: "same"))[0].errCode == -1102, "duplicate active call id rejected")
session.invalidate(); pump()
check(instances[0].disposed && instances[0].cancelled == 2, "navigation disposes and cancels")
check(pending.isEmpty, "invalid document has no callback")
session.beginDocument(url: URL(string: "https://example.com/two")!)
instances[0].late?.success("old"); instances[0].savedContext?.emit("finished", data: 2); pump()
check(events.count == 1 && pending.isEmpty, "old completion and event never reach new document")
let newDoc = (session.handshake().result as! [String: Any])["documentId"] as! String
check(newDoc != doc, "new document identity")
check(invoke(args("echo", document: newDoc))[0].errCode == 0 && created == 2, "new document creates new plugin")
trusted = false
check(session.handshake().errCode == -1006, "untrusted session rejected")
check(invoke(args("echo", document: newDoc))[0].errCode == -1006, "untrusted invocation rejected")
instances.last?.savedContext?.emit("finished", data: 3); pump()
check(events.count == 1, "untrusted event blocked")
// 同一文档复用已超时 callId 时，旧响应不能完成新的调用。
trusted = true
var firstReuse: [MWBResult] = []
session.invoke(args("wait", id: "reuse", timeout: 1, document: newDoc)) { firstReuse.append($0) }; pump()
let oldResponder = instances.last!.late!
var secondReuse: [MWBResult] = []
session.invoke(args("wait", id: "reuse", document: newDoc)) { secondReuse.append($0) }; pump()
oldResponder.success("obsolete"); pump()
check(secondReuse.isEmpty, "old responder cannot complete reused callId")
session.invalidate()
// network 仅在显式调用后发请求；响应及事件使用统一 wire。
session.beginDocument(url: url)
let networkDoc = (session.handshake().result as! [String: Any])["documentId"] as! String
check(network.requests.isEmpty, "network service has no startup request")
for badURL in ["http://example.com", "https://evil.example", "https://example.com.evil.test", "https://user:pass@example.com", "https://example.com:444"] {
    check(invoke(args("request", plugin: "network", document: networkDoc,
         params: ["url": badURL, "method": "GET"]))[0].errCode == -1102, "network URL policy")
}
check(invoke(args("request", plugin: "network", document: networkDoc,
     params: ["url": "https://example.com", "method": "DELETE"]))[0].errCode == -1102, "network method policy")
let getWithBody = invoke(args("request", plugin: "network", document: networkDoc,
    params: ["url": "https://example.com", "method": "GET", "body": "unexpected"]))
check(getWithBody.first?.errCode == -1102 && network.requests.isEmpty, "GET request body rejected before host service")
var networkResult: [MWBResult] = []
session.invoke(args("request", plugin: "network", document: networkDoc,
    params: ["url": "https://httpbin.org/post", "method": "POST", "headers": ["X-Test": "one"], "body": "hello"])) { networkResult.append($0) }
pump()
check(network.requests.count == 1 && network.requests[0].httpMethod == "POST" &&
      network.requests[0].httpBody == Data("hello".utf8), "host receives validated request")
network.callbacks[0](.success(.init(status: 201, headers: ["Content-Type": "text/plain"], body: "created"))); pump()
let response = networkResult[0].result as! [String: Any]
check(response["status"] as? Int == 201 && response["body"] as? String == "created", "HTTP response envelope")
check(events.last?["name"] as? String == "requestFinished" &&
      (events.last?["data"] as? [String: Any])?["status"] as? Int == 201, "network completion event")
session.invoke(args("request", timeout: 1, plugin: "network", document: networkDoc,
    params: ["url": "https://example.com", "method": "GET"])) { _ in }; pump()
check(network.cancelled == 1, "network timeout cancels host request")
session.invalidate()
// URLProtocol 只替代网络传输；运行真实 URLSession delegate 的流式限流和文本解码。
final class FixtureProtocol: URLProtocol {
    static var bytes = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 418, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // 无 Content-Length，确保实际收到的字节也被检查。
        client?.urlProtocol(self, didLoad: Self.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let fixtureConfiguration = URLSessionConfiguration.ephemeral
fixtureConfiguration.protocolClasses = [FixtureProtocol.self]
let realService = ExampleNetworkService(configuration: fixtureConfiguration)
for (bytes, expectedSuccess) in [(Data(repeating: 65, count: 1024 * 1024), true),
                                (Data(repeating: 65, count: 1024 * 1024 + 1), false),
                                (Data([0xFF, 0xFE]), false)] {
    FixtureProtocol.bytes = bytes
    var outcome: Result<ExampleNetworkResponse, Error>?
    _ = realService.send(URLRequest(url: URL(string: "https://example.com")!)) { result in
        DispatchQueue.main.async { outcome = result }
    }
    let until = Date().addingTimeInterval(2)
    while outcome == nil && Date() < until { pump(0.01) }
    check(outcome != nil, "URLSession fixture completes")
    switch outcome! {
    case .success(let response):
        check(expectedSuccess && response.status == 418 && response.body.utf8.count == 1024 * 1024,
              "exact response limit accepted and HTTP status preserved")
    case .failure:
        check(!expectedSuccess, "oversized or invalid UTF8 response rejected")
    }
}
// 执行时守卫覆盖 WebKit/DSBridge 排队之后主文档已替换的窗口。
let js = JSContext()!
js.evaluateScript("window=this; window.__mwbNativePluginDocumentId='new'; var hits=0; window.dscb0=()=>hits++;")
let oldScript = MWBPluginJavaScript.reply(callback: "dscb0", document: "old", result: .success("secret"))!
js.evaluateScript(oldScript)
check(js.objectForKeyedSubscript("hits").toInt32() == 0, "queued old reply blocked in new document")
let currentScript = MWBPluginJavaScript.reply(callback: "dscb0", document: "new", result: .success("ok"))!
js.evaluateScript(currentScript); js.evaluateScript(currentScript)
check(js.objectForKeyedSubscript("hits").toInt32() == 1, "current reply completes and deletes callback once")
check(MWBPluginJavaScript.reply(callback: "dscb0();evil()", document: "new", result: .success()) == nil,
      "callback expression injection rejected")
js.evaluateScript("window._dsf={'mwb.pluginEvent':()=>hits++}")
js.evaluateScript(MWBPluginJavaScript.event(["documentId":"old", "plugin":"network", "name":"done", "data":NSNull()]))
check(js.objectForKeyedSubscript("hits").toInt32() == 1, "queued event blocked in new document")
js.evaluateScript(MWBPluginJavaScript.event(["documentId":"new", "plugin":"network", "name":"done", "data":NSNull()]))
check(js.objectForKeyedSubscript("hits").toInt32() == 2, "current document event delivered")
// 宿主工厂可能同步发起导航；不能把已过期工厂返回的实例留给新文档。
session.beginDocument(url: url)
let reentrantDoc = (session.handshake().result as! [String: Any])["documentId"] as! String
factoryNavigation = { session.invalidate() }
session.invoke(args("echo", plugin: "reentrant", document: reentrantDoc)) { _ in }
pump()
check(reentrantPlugin.disposed && reentrantPlugin.savedContext == nil, "factory navigation disposes unbound instance")
// 相同定义快照的父子容器拥有不同实例和容器身份，子销毁不影响父。
let parentSession = MWBPluginSession(snapshot: snapshot, controller: nil, trustedURL: { url }, event: { _ in })
let childSession = MWBPluginSession(snapshot: snapshot, controller: nil, trustedURL: { url }, event: { _ in })
parentSession.beginDocument(url: url); childSession.beginDocument(url: url)
let parentDoc = (parentSession.handshake().result as! [String: Any])["documentId"] as! String
let childDoc = (childSession.handshake().result as! [String: Any])["documentId"] as! String
parentSession.invoke(args("echo", document: parentDoc)) { _ in }; pump()
let parentPlugin = instances.last!
childSession.invoke(args("echo", document: childDoc)) { _ in }; pump()
let childPlugin = instances.last!
check(parentPlugin !== childPlugin && parentPlugin.savedContext!.containerId != childPlugin.savedContext!.containerId,
      "child snapshot creates separate container plugin")
childSession.invalidate()
check(childPlugin.disposed && !parentPlugin.disposed, "child disposal preserves parent plugin")
parentSession.invalidate()

// 内置就绪通知必须复用文档校验，不能由 H5 任意指定新文档身份。
var readyCalls = 0
let readySession = MWBPluginSession(snapshot: [:], controller: nil, trustedURL: { url }, event: { _ in })
readySession.notifyPageReady = { readyCalls += 1; return .success() }
readySession.beginDocument(url: url)
let readyDoc = (readySession.handshake().result as! [String: Any])["documentId"] as! String
var readyResults: [MWBResult] = []
readySession.invoke(args("notifyPageReady", plugin: "basic", document: readyDoc)) { readyResults.append($0) }
check(readyResults.first?.errCode == 0 && readyCalls == 1, "builtin readiness dispatched")
readySession.beginDocument(url: url)
readySession.invoke(args("notifyPageReady", plugin: "basic", document: readyDoc)) { readyResults.append($0) }
check(readyResults.last?.errCode == -1104 && readyCalls == 1, "stale readiness rejected before callback")
let activeReadyDoc = (readySession.handshake().result as! [String: Any])["documentId"] as! String
readySession.invoke(args("notifyPageReady", plugin: "basic", document: activeReadyDoc, params: ["unexpected": true])) { readyResults.append($0) }
check(readyResults.last?.errCode == -1102, "builtin readiness accepts no parameters")
print("PASS: \(checks) native plugin and readiness contract checks")
