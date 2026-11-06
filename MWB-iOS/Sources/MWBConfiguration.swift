import Foundation

/// 宿主传入的页面地址与可信来源；来源使用 scheme、host 和可选端口组成。
public struct MWBConfiguration {
    public let initialURL: URL
    /// 默认 ["*"] 允许所有 HTTP(S) 页面加载并使用原生桥；显式空集合仅允许包内文件。
    public let allowedOrigins: Set<String>
    public let errorPage: MWBErrorPageConfiguration

    public init(initialURL: URL, allowedOrigins: Set<String> = ["*"], errorPage: MWBErrorPageConfiguration = .init()) {
        self.initialURL = initialURL
        self.allowedOrigins = allowedOrigins
        self.errorPage = errorPage
    }

    /// 从字符串建立配置，避免把空地址交给 WebView。
    public static func make(initialURLString: String, allowedOrigins: Set<String> = ["*"], errorPage: MWBErrorPageConfiguration = .init()) -> Self? {
        guard let url = URL(string: initialURLString), url.scheme != nil else { return nil }
        return Self(initialURL: url, allowedOrigins: allowedOrigins, errorPage: errorPage)
    }
}
