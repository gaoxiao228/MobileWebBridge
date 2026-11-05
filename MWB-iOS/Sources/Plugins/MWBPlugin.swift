import Foundation
import ObjectiveC.runtime

/// 异步业务插件基类；子类只声明固定 selector，不维护方法表。
open class MWBPlugin: NSObject {
    private var cachedMethods: Result<[String: Method], Error>?
    open func dispose() {}

    /// Core 的 final 入口阻止业务插件替换分发与签名校验。
    final func handle(method name: String, params: Any?, context: MWBPluginCallContext,
                      responder: MWBPluginResponder) {
        if cachedMethods == nil { cachedMethods = Result { try discoverMethods() } }
        do {
            let methods = try cachedMethods!.get()
            guard let method = methods[name] else {
                responder.failure(-1101, message: "Plugin method is unsupported"); return
            }
            // 仅在完整验证 void + 三个对象参数 ABI 后调用实现，绝不对任意 selector 强转。
            typealias Implementation = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject, AnyObject) -> Void
            let implementation = unsafeBitCast(method_getImplementation(method), to: Implementation.self)
            let exception = MWBPluginTry {
                implementation(self, method_getName(method), params as AnyObject?, context, responder)
            }
            if exception != nil { responder.failure(-1105, message: "Native plugin method failed") }
        } catch { responder.failure(-1105, message: "Invalid native plugin method signature") }
    }

    private func discoverMethods() throws -> [String: Method] {
        var result: [String: Method] = [:]
        var current: AnyClass? = type(of: self)
        while let cls = current, cls !== MWBPlugin.self {
            var count: UInt32 = 0
            let methods = class_copyMethodList(cls, &count)
            defer { free(methods) }
            for index in 0..<Int(count) {
                let method = methods![index]
                let selector = NSStringFromSelector(method_getName(method))
                guard selector.hasPrefix("mwb_") else { continue }
                let parts = selector.components(separatedBy: ":")
                guard parts.count == 4, parts[1] == "context", parts[2] == "responder", parts[3].isEmpty else {
                    throw MWBPluginConfigurationError.invalidSignature
                }
                let name = String(parts[0].dropFirst(4))
                let returnType = method_copyReturnType(method)
                defer { free(returnType) }
                guard MWBPluginNames.validMember(name), result[name] == nil,
                      String(cString: returnType) == "v", method_getNumberOfArguments(method) == 5 else {
                    throw MWBPluginConfigurationError.invalidSignature
                }
                for argument in UInt32(2)...4 {
                    let type = method_copyArgumentType(method, argument)!
                    defer { free(type) }
                    // Swift 的 ObjC 编码仅保留对象 ABI，不保留对象的具体 Swift 类。
                    guard String(cString: type) == "@" else { throw MWBPluginConfigurationError.invalidSignature }
                }
                result[name] = method
            }
            current = class_getSuperclass(cls)
        }
        return result
    }
}

/// 配置错误直接在宿主注册时抛出，不伪装为成功。
public enum MWBPluginConfigurationError: Error {
    case invalidName, duplicateName, registrationClosed, invalidSignature
}

/// 进程级注册；第一个容器取得快照之后不可修改。
public enum MWB {
    private static let registry = MWBPluginRegistry()
    public static func registerPlugin(name: String, factory: @escaping () throws -> MWBPlugin) throws {
        try registry.register(name: name, factory: factory)
    }
    static func pluginSnapshot() -> MWBPluginSnapshot { registry.snapshot() }
}

typealias MWBPluginSnapshot = [String: () throws -> MWBPlugin]
final class MWBPluginRegistry {
    private let lock = NSLock()
    private var definitions: MWBPluginSnapshot = [:]
    private var frozen = false
    func register(name: String, factory: @escaping () throws -> MWBPlugin) throws {
        lock.lock(); defer { lock.unlock() }
        guard !frozen else { throw MWBPluginConfigurationError.registrationClosed }
        guard MWBPluginNames.validPlugin(name) else { throw MWBPluginConfigurationError.invalidName }
        guard definitions[name] == nil else { throw MWBPluginConfigurationError.duplicateName }
        definitions[name] = factory
    }
    func snapshot() -> MWBPluginSnapshot {
        lock.lock(); defer { lock.unlock() }
        frozen = true
        return definitions
    }
}

/// JS 根成员和 Promise/对象探测成员不可被业务插件覆盖。
enum MWBPluginNames {
    static let reserved: Set<String> = Set("""
    notifyPageReady basic version hasPlugin pluginSession pluginInfo invokePlugin pluginEvent Core dispatchEvent backBtnPressed
    setEnableDebug toast navigateTo navigateBack navigateBackToRoot openExternalBrowser setNavigationBarTheme
    cleanWebviewCache exitApp openNativePage openAppAuthorizeSetting getAppInfoSync setBadgeCount
    getDeviceInfoSync getClipboardDataSync setClipboardData makePhoneCall getNetworkTypeSync
    getNotificationSwitchStatus compressImage scanCode saveImageToPhotosAlbum chooseImage openFile
    checkRequestCameraPermissions convertImagePathToBase64 setStorageSync getStorageSync removeStorageSync clearStorageSync
    registerHandler unRegisterHandlers unRegisterHandler checkHandlerExist onNetworkStatusChange offNetworkStatusChange
    onAppShow offAppShow onAppHide offAppHide onRemoteNotificationReceive offRemoteNotificationReceive
    onPageShow offPageShow onPageHide offPageHide onBackBtnPressed offBackBtnPressed
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    static let members: Set<String> = ["on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__"]
    static func valid(_ name: String) -> Bool {
        name.range(of: "^[a-z][a-zA-Z0-9_]*$", options: .regularExpression) != nil
    }
    static func validMember(_ name: String) -> Bool { valid(name) && !members.contains(name) }
    static func validPlugin(_ name: String) -> Bool { validMember(name) && !reserved.contains(name) }
}

/// JSON 通过真实序列化验证，保留显式 NSNull 并拒绝 NaN/原生对象。
func mwbPluginJSON(_ value: Any) -> Bool {
    JSONSerialization.isValidJSONObject(["value": value])
}

/// 每个调用的取消登记允许宿主在任意线程使用。
final class MWBPluginCancellation {
    private let lock = NSLock()
    private var handlers: [() -> Void] = []
    private var closed = false
    private var cancelled = false
    func register(_ handler: @escaping () -> Void) {
        lock.lock()
        if closed { let call = cancelled; lock.unlock(); if call { _ = MWBPluginTry { handler() } }; return }
        handlers.append(handler); lock.unlock()
    }
    func finish(cancel: Bool) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true; cancelled = cancel
        let pending = handlers; handlers.removeAll(); lock.unlock()
        if cancel { pending.forEach { handler in _ = MWBPluginTry { handler() } } }
    }
}

/// Objective-C 可表示的上下文，只能向其所属插件和文档发送事件。
@objc public final class MWBPluginCallContext: NSObject {
    @objc public let containerId: String
    @objc public let documentId: String
    @objc public let pageURL: URL
    private weak var ownerController: MWBWebViewController?
    private let isActive: () -> Bool
    @objc public var controller: MWBWebViewController? { isActive() ? ownerController : nil }
    private let emitEvent: (String, Any?) -> Void
    private let cancellation: MWBPluginCancellation
    init(containerId: String, documentId: String, pageURL: URL, controller: MWBWebViewController?,
         cancellation: MWBPluginCancellation, isActive: @escaping () -> Bool, emit: @escaping (String, Any?) -> Void) {
        self.containerId = containerId; self.documentId = documentId; self.pageURL = pageURL
        self.ownerController = controller; self.cancellation = cancellation; self.emitEvent = emit; self.isActive = isActive
    }
    @objc public func emit(_ name: String, data: Any? = nil) { emitEvent(name, data) }
    @objc public func onCancel(_ handler: @escaping () -> Void) { cancellation.register(handler) }
}

/// 线程安全的一次响应；nil 省略 result，NSNull 保留 result:null。
@objc public final class MWBPluginResponder: NSObject {
    private let lock = NSLock()
    private var completion: ((MWBResult) -> Void)?
    init(completion: @escaping (MWBResult) -> Void) { self.completion = completion }
    @objc public func success(_ result: Any? = nil) {
        if let result, !mwbPluginJSON(result) {
            finish(.failure(-1102, "Plugin result is not JSON")); return
        }
        finish(.success(result))
    }
    @objc public func failure(_ code: Int, message: String) { finish(.failure(code, message)) }
    func finish(_ result: MWBResult) {
        lock.lock(); let callback = completion; completion = nil; lock.unlock()
        callback?(result)
    }
}
