import Foundation

/// 宿主传入的页面地址与可信来源；来源使用 scheme、host 和可选端口组成。
public struct MWBConfiguration {
    public let initialURL: URL
    public let allowedOrigins: Set<String>

    public init(initialURL: URL, allowedOrigins: Set<String>) {
        self.initialURL = initialURL
        self.allowedOrigins = allowedOrigins
    }

    /// 从字符串建立配置，避免把空地址交给 WebView。
    public static func make(initialURLString: String, allowedOrigins: Set<String>) -> Self? {
        guard let url = URL(string: initialURLString), url.scheme != nil else { return nil }
        return Self(initialURL: url, allowedOrigins: allowedOrigins)
    }
}
