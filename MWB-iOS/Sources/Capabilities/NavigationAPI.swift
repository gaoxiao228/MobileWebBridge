import UIKit
import WebKit
import CoreFoundation

/// 页面与 WebView 控制方法均在主线程操作 UIKit。
extension MWBBridgeAdapter {
    @objc func setEnableDebug(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        let enabled = (arg as? [String: Any])?["enabled"] as? Bool ?? false
        controller?.webView?.setDebugMode(enabled)
        if #available(iOS 16.4, *) { controller?.webView?.isInspectable = enabled }
        return NSNull()
    }

    @objc func toast(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let message = (arg as? [String: Any])?["msg"] as? String else {
            respond(.failure(-1001, "Toast message is required"), with: handler)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let controller = self?.controller else { return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            controller.present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak alert] in
                alert?.dismiss(animated: true)
            }
            self?.respond(.success(), with: handler)
        }
    }

    @objc func navigateTo(_ arg: Any?, handler: @escaping MWBJSCallback) {
        navigate(arg, replacingCurrent: false, handler: handler)
    }

    /// 替换当前导航栈顶，不把旧容器留下供后续返回。
    @objc func redirectTo(_ arg: Any?, handler: @escaping MWBJSCallback) {
        navigate(arg, replacingCurrent: true, handler: handler)
    }

    private func navigate(_ arg: Any?, replacingCurrent: Bool, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let params = arg as? [String: Any],
              let text = params["url"] as? String,
              let url = URL(string: text),
              let controller, controller.isTrusted(url) else {
            respond(.failure(-1001, "Invalid or untrusted URL"), with: handler)
            return
        }
        // 未实现的旧项目参数继续明确拒绝。
        let supported = replacingCurrent ? ["url", "title", "hidden", "waitForReady"] :
            ["url", "title", "hidden", "isPopUp", "waitForReady"]
        let unsupported = params.keys.filter { !supported.contains($0) }
        guard unsupported.isEmpty else {
            let method = replacingCurrent ? "redirectTo" : "navigateTo"
            respond(.failure(-1004, "Unsupported \(method) options: \(unsupported.joined(separator: ", "))"), with: handler)
            return
        }
        // 新接口严格校验基础字段，不改变旧 navigateTo 对历史参数的处理方式。
        if replacingCurrent {
            if let title = params["title"], !(title is String) {
                respond(.failure(-1001, "title must be a string"), with: handler)
                return
            }
            if let hidden = params["hidden"],
               !(hidden is NSNumber && CFGetTypeID(hidden as CFTypeRef) == CFBooleanGetTypeID()) {
                respond(.failure(-1001, "hidden must be a boolean"), with: handler)
                return
            }
        }
        // NSNumber 的 0/1 不能当成 JSON boolean 接受。
        if let option = params["waitForReady"],
           !(option is NSNumber && CFGetTypeID(option as CFTypeRef) == CFBooleanGetTypeID()) {
            respond(.failure(-1001, "waitForReady must be a boolean"), with: handler)
            return
        }
        let sourceRevision = controller.documentRevision
        DispatchQueue.main.async {
            // JS 发出请求后、主队列开始准备前，来源也可能已整页导航。
            guard controller.documentRevision == sourceRevision else { return }
            guard controller.pendingNavigation == nil, controller.navigationPreparation == nil else {
                self.respond(.failure(-1004, "Navigation preparation is already pending"), with: handler)
                return
            }
            // 没有导航栈时不能降级为 present，否则旧页面仍留在返回路径中。
            if replacingCurrent {
                guard let navigation = controller.navigationController,
                      navigation.topViewController === controller, controller.canStartPreparedNavigation else {
                    self.respond(.failure(-1004, "Current page cannot be replaced outside an idle navigation stack"), with: handler)
                    return
                }
            }
            let next = MWBWebViewController(configuration: controller.configuration)
            next.host = controller.host
            next.initialPageOverride = url
            next.initialNavigationBarHidden = params["hidden"] as? Bool ?? true
            next.title = params["title"] as? String
            let show: (MWBWebViewController) -> Void = { [weak controller] next in
                guard let controller else { return }
                if replacingCurrent {
                    guard let navigation = controller.navigationController,
                          navigation.topViewController === controller else { return }
                    // 一次替换栈顶，保留 P；根页面也直接替换，不短暂展示中间页面。
                    navigation.setViewControllers(Array(navigation.viewControllers.dropLast()) + [next], animated: false)
                    controller.retireAfterReplacement()
                } else if params["isPopUp"] as? Bool == true {
                    controller.present(UINavigationController(rootViewController: next), animated: true)
                } else if let navigationController = controller.navigationController {
                    navigationController.pushViewController(next, animated: true)
                } else {
                    controller.present(next, animated: true)
                }
            }
            if params["waitForReady"] as? Bool == true {
                let preparation = MWBNavigationPreparation(source: controller, target: next, show: show) {
                    self.respond($0, with: handler)
                }
                controller.pendingNavigation = preparation
                preparation.start()
            } else {
                show(next)
                self.respond(.success(), with: handler)
            }
        }
    }

    @objc func navigateBack(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let controller else {
            respond(.failure(-1005, "Container is unavailable"), with: handler)
            return
        }
        DispatchQueue.main.async {
            if let navigationController = controller.navigationController,
               navigationController.viewControllers.count > 1 {
                if let previous = navigationController.viewControllers.dropLast().last as? MWBWebViewController {
                    previous.sendEvent("navigateBack", data: arg)
                }
                navigationController.popViewController(animated: true)
            } else if controller.presentingViewController != nil {
                controller.dismiss(animated: true)
            } else {
                self.respond(.failure(-1004, "No page to go back to"), with: handler)
                return
            }
            self.respond(.success(), with: handler)
        }
    }

    @objc func navigateBackToRoot(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.controller,
                  let navigationController = controller.navigationController else {
                self?.respond(.failure(-1005, "Navigation controller is unavailable"), with: handler)
                return
            }
            navigationController.popToRootViewController(animated: true)
            self.respond(.success(), with: handler)
        }
    }

    @objc func openExternalBrowser(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let text = (arg as? [String: Any])?["url"] as? String,
              let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            respond(.failure(-1001, "Invalid external URL"), with: handler)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url) { success in
                self.respond(success ? .success() : .failure(-1002, "Cannot open URL"), with: handler)
            }
        }
    }

    @objc func setNavigationBarTheme(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        let params = arg as? [String: Any] ?? [:]
        // 未实现的主题字段明确报错，避免网页误以为按钮或状态栏已更新。
        let unsupported = ["showBackButton", "showCloseButton", "isBright",
                           "actionIcon", "translucentStatusBars"]
        guard !unsupported.contains(where: { params[$0] != nil }) else {
            respond(.failure(-1004, "Unsupported navigation theme"), with: handler)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.controller else { return }
            if let title = params["title"] as? String { controller.title = title }
            if let hidden = params["hidden"] as? Bool {
                controller.navigationController?.setNavigationBarHidden(hidden, animated: false)
            }
            if params["actionTxt"] != nil || params["actionExt"] != nil {
                let title = params["actionTxt"] as? String ?? controller.navigationItem.rightBarButtonItem?.title
                controller.configureNavigationAction(title: title, ext: params["actionExt"] as? String)
            }
            let background = (params["color"] as? String).flatMap(UIColor.init(mwbHex:))
            let titleColor = (params["titleColor"] as? String).flatMap(UIColor.init(mwbHex:))
            if let bar = controller.navigationController?.navigationBar,
               background != nil || titleColor != nil {
                let appearance = bar.standardAppearance.copy()
                if let background {
                    let previousTitleStyle = appearance.titleTextAttributes
                    appearance.configureWithOpaqueBackground()
                    appearance.backgroundColor = background
                    appearance.titleTextAttributes = previousTitleStyle
                    bar.backgroundColor = background
                }
                if let titleColor {
                    appearance.titleTextAttributes[.foregroundColor] = titleColor
                    bar.titleTextAttributes = [.foregroundColor: titleColor]
                    bar.tintColor = titleColor
                }
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance.copy()
            }
            controller.rememberNavigationBarState()
            self.respond(.success(), with: handler)
        }
    }

    @objc func cleanWebviewCache(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        let dataStore = WKWebsiteDataStore.default()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { [weak self] in
            self?.respond(.success(), with: handler)
        }
    }
}

private extension UIColor {
    convenience init?(mwbHex: String) {
        let value = mwbHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(red: CGFloat((number >> 16) & 0xff) / 255,
                  green: CGFloat((number >> 8) & 0xff) / 255,
                  blue: CGFloat(number & 0xff) / 255, alpha: 1)
    }
}
