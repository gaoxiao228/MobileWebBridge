import Foundation

/// 允许精确匹配的 HTTP(S) 来源和包内文件；单独的 * 允许全部 HTTP(S) 来源使用原生桥。
public struct MWBNavigationPolicy {
    private let allowedOrigins: Set<String>
    private let allowsAllHttpOrigins: Bool
    private let localRoot: URL?

    public init(allowedOrigins: Set<String>, localRoot: URL? = nil) {
        self.allowsAllHttpOrigins = allowedOrigins.contains("*")
        self.allowedOrigins = Set(allowedOrigins.compactMap { URL(string: $0) }.compactMap(Self.origin))
        self.localRoot = localRoot?.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func isTrusted(_ url: URL) -> Bool {
        if url.isFileURL, let localRoot {
            guard let path = Self.resolvedLocalURL(url)?.path else { return false }
            return path == localRoot.path || path.hasPrefix(localRoot.path + "/")
        }
        guard let origin = Self.origin(url) else { return false }
        // 先校验来源协议，星号不能绕过本地文件和其他协议的限制。
        return allowsAllHttpOrigins || allowedOrigins.contains(origin)
    }

    /// 缺失入口也应按实际所在目录判断信任，再由 WebView 报告资源加载失败。
    private static func resolvedLocalURL(_ url: URL) -> URL? {
        let manager = FileManager.default
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        // Foundation 对不存在的完整路径可能不解析父级符号链接；先找到存在的祖先。
        while !manager.fileExists(atPath: ancestor.path) {
            let type = (try? manager.attributesOfItem(atPath: ancestor.path))?[.type] as? FileAttributeType
            // 断开的符号链接不能视作普通缺失目录，否则可能漏掉指向包外的目标。
            if type == .typeSymbolicLink { return nil }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return nil }
            missingComponents.append(ancestor.lastPathComponent)
            ancestor = parent
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
