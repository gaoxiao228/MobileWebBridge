import Foundation

typealias MWBJSCallback = (String, Bool) -> Void

/// DSBridge 按 Objective-C 可见的方法名暴露 API，此对象集中处理安全检查与宿主扩展。
final class MWBBridgeAdapter: NSObject {
    weak var controller: MWBWebViewController?
    let storage = MWBStorage()
    lazy var mediaCoordinator = MWBMediaCoordinator(controller: controller)

    init(controller: MWBWebViewController) {
        self.controller = controller
    }

    var isTrusted: Bool {
        guard let controller else { return false }
        return controller.isTrusted(controller.webView?.url ?? controller.configuration.initialURL)
    }

    func respond(_ result: MWBResult, with callback: MWBJSCallback) {
        callback(result.jsonString, true)
    }

    func rejectUntrusted(_ callback: MWBJSCallback) -> Bool {
        guard !isTrusted else { return false }
        respond(.failure(-1006, "Untrusted page"), with: callback)
        return true
    }

    @objc func getAppInfoSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        return controller?.host?.appInfo() ?? MWBResult.failure(-1005, "App info is not configured").dictionary
    }

    @objc func exitApp(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard isTrusted else {
            respond(.failure(-1006, "Untrusted page"), with: handler)
            return
        }
        respond(.failure(-1004, "exitApp is unsupported on iOS"), with: handler)
    }

    @objc func openNativePage(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard isTrusted else {
            respond(.failure(-1006, "Untrusted page"), with: handler)
            return
        }
        guard let params = arg as? [String: Any],
              let name = params["pageName"] as? String, !name.isEmpty,
              let page = controller?.host?.nativePage(named: name, extInfo: params["extInfo"] as? [String: Any]) else {
            respond(.failure(-1005, "Native page is not registered"), with: handler)
            return
        }
        guard let controller else {
            respond(.failure(-1005, "Container is unavailable"), with: handler)
            return
        }
        if let navigationController = controller.navigationController {
            navigationController.pushViewController(page, animated: true)
        } else {
            controller.present(page, animated: true)
        }
        respond(.success(), with: handler)
    }
}

/// 插件网关独立于 basic；不把业务对象直接注册到 DSBridge。
extension MWBBridgeAdapter {
    @objc func pluginSession(_ arg: Any?) -> Any {
        guard let controller, controller.isPluginBridgeTrusted else {
            return MWBResult.failure(-1006, "Untrusted main document").dictionary
        }
        guard arg == nil || arg is NSNull else {
            return MWBResult.failure(-1102, "pluginSession takes no parameters").dictionary
        }
        return controller.pluginSession.handshake().dictionary
    }
    @objc func pluginInfo(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard let controller, controller.isPluginBridgeTrusted else {
            respond(.failure(-1006, "Untrusted main document"), with: handler); return
        }
        respond(controller.pluginSession.info(arg), with: controller.pluginBridgeReply ?? handler)
    }
    @objc func invokePlugin(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard let controller, controller.isPluginBridgeTrusted else {
            respond(.failure(-1006, "Untrusted main document"), with: handler); return
        }
        let reply = controller.pluginBridgeReply ?? handler
        controller.pluginSession.invoke(arg) { result in reply(result.jsonString, true) }
    }
}
