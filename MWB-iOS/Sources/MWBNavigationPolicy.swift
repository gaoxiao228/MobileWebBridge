import Foundation

/// 仅允许完全匹配的 HTTPS/HTTP 来源和宿主 App 包内文件使用原生桥。
public struct MWBNavigationPolicy {
    private let allowedOrigins: Set<String>
    private let localRoot: URL?

    public init(allowedOrigins: Set<String>, localRoot: URL? = nil) {
        self.allowedOrigins = Set(allowedOrigins.compactMap { URL(string: $0) }.compactMap(Self.origin))
        self.localRoot = localRoot?.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func isTrusted(_ url: URL) -> Bool {
        if url.isFileURL, let localRoot {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            return path == localRoot.path || path.hasPrefix(localRoot.path + "/")
        }
        guard let origin = Self.origin(url) else { return false }
        return allowedOrigins.contains(origin)
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
