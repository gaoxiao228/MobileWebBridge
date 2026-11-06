import Foundation

/// 本地错误模板可以来自 SDK 或宿主显式指定的资源 Bundle。
public enum MWBErrorPageSource {
    case builtIn
    case bundled(bundle: Bundle, directory: String, entry: String)
}

public struct MWBErrorPageConfiguration {
    public let enabled: Bool
    public let source: MWBErrorPageSource
    public init(enabled: Bool = true, source: MWBErrorPageSource = .builtIn) {
        self.enabled = enabled; self.source = source
    }
}

/// 仅供原生排查的诊断数据；错误 HTML 不接收 URL 或原始异常文本。
public struct MWBPageLoadError {
    public enum Kind: String { case network, timeout, http, tls, localResource, rendererTerminated, blockedNavigation }
    public let kind: Kind
    public let url: URL
    public let method: String?
    public let message: String
    public let httpStatus: Int?
    public var canRetry: Bool { method == "GET" && kind != .blockedNavigation }
    var userMessage: String {
        switch kind {
        case .network: return "连接暂时不可用，请检查网络后重试。"
        case .timeout: return "连接等待时间过长，请重新加载。"
        case .http: return httpStatus == 404 ? "这个页面暂时找不到了，可以重新加载或返回首页。" : "服务暂时不可用，请稍后重试。"
        case .tls: return "无法建立安全连接，请稍后重试。"
        case .localResource: return "页面资源暂时无法读取，请重新加载。"
        case .rendererTerminated: return "页面意外中断，请重新加载。"
        case .blockedNavigation: return "暂时无法打开这个地址，请返回首页。"
        }
    }
}

/// 所有路径解析集中校验，子资源也不能越过指定根目录。
enum MWBErrorPageResources {
    static var builtInBundle: Bundle? {
        for parent in [Bundle(for: MWBWebViewController.self), Bundle.main] {
            if let url = parent.url(forResource: "MobileWebBridgeErrorPage", withExtension: "bundle"),
               let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }
    static func root(for source: MWBErrorPageSource) -> URL? {
        switch source {
        case .builtIn: return builtInBundle?.resourceURL
        case let .bundled(bundle, directory, _):
            guard let root = bundle.resourceURL else { return nil }
            if directory.isEmpty { return root }
            return file(directory, root: root)
        }
    }
    static func file(_ path: String, root: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("%"), !path.contains("\\"),
              !path.contains(":"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let target = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard target.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }
}
