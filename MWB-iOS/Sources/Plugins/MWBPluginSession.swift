import Foundation
import CoreFoundation


/// 文档身份、惰性实例和 pending 统一由主线程拥有；隐藏页面不撤销身份。
final class MWBPluginSession {
    private struct Pending {
        let token: UUID
        let responder: MWBPluginResponder
        let cancellation: MWBPluginCancellation
        let timer: DispatchWorkItem
        let deadline: TimeInterval
        let callback: (MWBResult) -> Void
    }
    /// 内置能力由所属容器安装，仍经过下面的文档与协议校验。
    var notifyPageReady: (() -> MWBResult)?
    private let snapshot: MWBPluginSnapshot
    private weak var controller: MWBWebViewController?
    private let trustedURL: () -> URL?
    private let event: ([String: Any]) -> Void
    private let containerId = UUID().uuidString
    private var documentId: String?
    var identity: String? { documentId }
    private var pageURL: URL?
    private var instances: [String: MWBPlugin] = [:]
    private var pending: [String: Pending] = [:]

    init(snapshot: MWBPluginSnapshot, controller: MWBWebViewController?,
         trustedURL: @escaping () -> URL?, event: @escaping ([String: Any]) -> Void) {
        self.snapshot = snapshot; self.controller = controller; self.trustedURL = trustedURL; self.event = event
    }
    func beginDocument(url: URL) {
        invalidate()
        pageURL = url; documentId = UUID().uuidString
    }
    func invalidate() {
        documentId = nil; pageURL = nil
        let calls = pending; pending.removeAll()
        // 先撤销授权和回调，再通知宿主取消，避免同步取消回调重入。
        calls.values.forEach { $0.timer.cancel(); $0.cancellation.finish(cancel: true) }
        let plugins = instances; instances.removeAll()
        plugins.values.forEach { plugin in _ = MWBPluginTry { plugin.dispose() } }
    }
    deinit { invalidate() }

    func handshake() -> MWBResult {
        guard trustedURL() != nil else { return .failure(-1006, "Untrusted page") }
        guard let documentId else { return .failure(-1104, "Document is unavailable") }
        return .success(["protocol": 1, "documentId": documentId])
    }
    private func validate(_ value: Any?) -> Result<[String: Any], MWBPluginGatewayError> {
        guard trustedURL() != nil else { return .failure(.init(code: -1006)) }
        guard let args = value as? [String: Any], mwbPluginJSON(args) else { return .failure(.init(code: -1102)) }
        guard let version = args["protocol"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1 else {
            return .failure(.init(code: -1106))
        }
        guard let doc = args["documentId"] as? String, let documentId, doc == documentId else {
            return .failure(.init(code: -1104))
        }
        guard let plugin = args["plugin"] as? String,
              plugin == "basic" || MWBPluginNames.validPlugin(plugin) else { return .failure(.init(code: -1102)) }
        return .success(args)
    }
    func info(_ value: Any?) -> MWBResult {
        switch validate(value) {
        case .failure(let error): return error.result
        case .success(let args):
            let name = args["plugin"] as! String
            return .success(["available": name == "basic" || snapshot[name] != nil])
        }
    }
    func invoke(_ value: Any?, callback: @escaping (MWBResult) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.invoke(value, callback: callback) }; return
        }
        let args: [String: Any]
        switch validate(value) {
        case .failure(let error): callback(error.result); return
        case .success(let result): args = result
        }
        guard let name = args["plugin"] as? String,
              let method = args["method"] as? String, MWBPluginNames.validMember(method),
              let callId = args["callId"] as? String, !callId.isEmpty,
              pending[callId] == nil else { callback(.failure(-1102, "Invalid plugin invocation")); return }
        let timeout: Double
        if let raw = args["timeoutMs"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue,
                  (1...120000).contains(number.doubleValue) else {
                callback(.failure(-1102, "Invalid timeoutMs")); return
            }
            timeout = number.doubleValue / 1000
        } else { timeout = 30 }
        if name == "basic" {
            guard method == "notifyPageReady" else { callback(.failure(-1101, "Builtin method is unsupported")); return }
            guard args["params"] == nil || args["params"] is NSNull else {
                callback(.failure(-1102, "notifyPageReady takes no parameters")); return
            }
            callback(notifyPageReady?() ?? .failure(-1106, "Page readiness is unavailable"))
            return
        }
        guard let factory = snapshot[name], let doc = documentId, let pageURL else {
            callback(.failure(name == "basic" ? -1101 : -1100, "Plugin is unavailable")); return
        }
        let cancellation = MWBPluginCancellation()
        let token = UUID()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let responder = MWBPluginResponder { [weak self] result in
            // 回调始终异步归主线程，工厂和方法的同步完成也服从同一状态机。
            DispatchQueue.main.async { self?.complete(callId: callId, token: token, document: doc, result: result) }
        }
        let timer = DispatchWorkItem { [weak self] in
            self?.complete(callId: callId, token: token, document: doc, result: .failure(-1103, "Plugin call timed out"))
        }
        pending[callId] = Pending(token: token, responder: responder, cancellation: cancellation, timer: timer,
                                  deadline: deadline, callback: callback)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
        let context = MWBPluginCallContext(containerId: containerId, documentId: doc, pageURL: pageURL,
            controller: controller, cancellation: cancellation,
            isActive: { [weak self] in self?.documentId == doc && self?.trustedURL() != nil }) { [weak self] eventName, data in
            DispatchQueue.main.async {
                guard let self, self.documentId == doc, self.trustedURL() != nil,
                      MWBPluginNames.validMember(eventName), mwbPluginJSON(data ?? NSNull()) else { return }
                self.event(["documentId": doc, "plugin": name, "name": eventName, "data": data ?? NSNull()])
            }
        }
        do {
            let plugin: MWBPlugin
            if let existing = instances[name] { plugin = existing }
            else {
                var created: Result<MWBPlugin, Error>?
                let exception = MWBPluginTry { created = Result { try factory() } }
                guard exception == nil, let created else {
                    responder.failure(-1105, message: "Plugin factory failed"); return
                }
                plugin = try created.get()
                guard documentId == doc else {
                    _ = MWBPluginTry { plugin.dispose() }
                    return
                }
                instances[name] = plugin
            }
            guard ProcessInfo.processInfo.systemUptime < deadline, documentId == doc, trustedURL() != nil else {
                complete(callId: callId, token: token, document: doc,
                         result: .failure(-1103, "Plugin call timed out before method entry"))
                return
            }
            plugin.handle(method: method, params: args["params"] ?? NSNull(), context: context, responder: responder)
        } catch { responder.failure(-1105, message: "Plugin factory failed") }
    }
    private func complete(callId: String, token: UUID, document: String, result: MWBResult) {
        guard documentId == document, let call = pending[callId], call.token == token else { return }
        pending.removeValue(forKey: callId)
        call.timer.cancel()
        guard trustedURL() != nil else { call.cancellation.finish(cancel: true); return }
        let timedOut = result.errCode == -1103 || ProcessInfo.processInfo.systemUptime >= call.deadline
        call.cancellation.finish(cancel: timedOut)
        call.callback(timedOut ? .failure(-1103, "Plugin call timed out") : result)
    }
}

private struct MWBPluginGatewayError: Error {
    let code: Int
    var result: MWBResult { .failure(code, "Plugin gateway rejected the request") }
}
