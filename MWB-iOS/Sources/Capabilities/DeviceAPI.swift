import UIKit
import Network
import CoreTelephony
import UserNotifications

/// 网络状态以系统回调更新，同步 JS API 读取最近一次结果。
final class MWBNetworkState {
    static let shared = MWBNetworkState()
    static let changed = Notification.Name("MWBNetworkStatusChanged")
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var status = "unknown"

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next = Self.map(path)
            self.lock.lock()
            let changed = self.status != next
            self.status = next
            self.lock.unlock()
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.changed, object: next)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "org.mobilewebbridge.network"))
    }

    var current: String {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    private static func map(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
        if path.usesInterfaceType(.cellular) {
            let technology = CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology?.values.first ?? ""
            if technology == CTRadioAccessTechnologyNR || technology == CTRadioAccessTechnologyNRNSA { return "5g" }
            if technology == CTRadioAccessTechnologyLTE { return "4g" }
            if [CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
                CTRadioAccessTechnologyHSUPA].contains(technology) { return "3g" }
            return "2g"
        }
        return "unknown"
    }
}

/// 系统设置、设备信息和宿主提供的应用数据。
extension MWBBridgeAdapter {
    @objc func openAppAuthorizeSetting(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            respond(.failure(-1002, "Settings URL is unavailable"), with: handler)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url) { success in
                self.respond(success ? .success() : .failure(-1002, "Cannot open settings"), with: handler)
            }
        }
    }

    @objc func setBadgeCount(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let count = (arg as? [String: Any])?["count"] as? Int, count >= 0 else {
            respond(.failure(-1001, "Invalid badge count"), with: handler)
            return
        }
        DispatchQueue.main.async {
            let success = self.controller?.host?.setBadgeCount(count) ?? false
            self.respond(success ? .success() : .failure(-1005, "Badge capability is not configured"),
                         with: handler)
        }
    }

    @objc func getDeviceInfoSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        let window = controller?.viewIfLoaded?.window
        let statusBarHeight = window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        return [
            "osType": 2,
            "osVersion": UIDevice.current.systemVersion,
            "model": UIDevice.current.model,
            "brand": "Apple",
            "deviceId": controller?.host?.deviceID() ?? UIDevice.current.identifierForVendor?.uuidString ?? "",
            "statusBarHeight": statusBarHeight,
            "bottomSafeAreaHeight": window?.safeAreaInsets.bottom ?? 0
        ] as [String: Any]
    }

    @objc func getClipboardDataSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        return ["data": UIPasteboard.general.string ?? ""]
    }

    @objc func setClipboardData(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let value = (arg as? [String: Any])?["data"] as? String else {
            respond(.failure(-1001, "Clipboard data is required"), with: handler)
            return
        }
        DispatchQueue.main.async {
            UIPasteboard.general.string = value
            self.respond(.success(), with: handler)
        }
    }

    @objc func makePhoneCall(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let number = (arg as? [String: Any])?["phoneNumber"] as? String,
              !number.isEmpty, number.range(of: "^[+0-9*#]+$", options: .regularExpression) != nil,
              let url = URL(string: "tel:\(number)") else {
            respond(.failure(-1001, "Invalid phone number"), with: handler)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url) { success in
                self.respond(success ? .success() : .failure(-1002, "Cannot make phone call"), with: handler)
            }
        }
    }

    @objc func getNetworkTypeSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        return ["networkType": MWBNetworkState.shared.current]
    }

    @objc func getNotificationSwitchStatus(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let enabled = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
            self.respond(.success(["status": enabled]), with: handler)
        }
    }
}
