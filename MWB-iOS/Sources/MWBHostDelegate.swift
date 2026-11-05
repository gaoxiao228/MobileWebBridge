import UIKit

/// 宿主应用提供的专属能力；未实现的方法由 MWB 返回“未配置”错误。
public protocol MWBHostDelegate: AnyObject {
    func appInfo() -> [String: Any]?
    func deviceID() -> String?
    func setBadgeCount(_ count: Int) -> Bool
    func nativePage(named name: String, extInfo: [String: Any]?) -> UIViewController?
}

public extension MWBHostDelegate {
    func appInfo() -> [String: Any]? { nil }
    func deviceID() -> String? { nil }
    func setBadgeCount(_ count: Int) -> Bool { false }
    func nativePage(named name: String, extInfo: [String: Any]?) -> UIViewController? { nil }
}
