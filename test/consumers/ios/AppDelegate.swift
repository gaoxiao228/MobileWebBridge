import UIKit
import MobileWebBridge

/// 消费者必须通过框架公开模块使用容器、配置、宿主与插件，避免示例工程内部可见性掩盖问题。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let host = ConsumerHost()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        do {
            try MWB.registerPlugin(name: "echo") { EchoPlugin() }
        } catch {
            preconditionFailure("Echo plugin registration failed: \(error)")
        }
        let configuration = MWBConfiguration(
            initialURL: URL(string: "https://example.com")!,
            allowedOrigins: ["https://example.com"]
        )
        // 编译覆盖关闭与 Bundle 自定义资源入口；无需访问 SDK 内部类型。
        _ = MWBConfiguration(initialURL: configuration.initialURL, allowedOrigins: [], errorPage: .init(enabled: false))
        _ = MWBConfiguration(initialURL: configuration.initialURL, allowedOrigins: [],
            errorPage: .init(source: .bundled(bundle: .main, directory: "custom-error", entry: "index.html")))
        let controller = ConsumerWebController(configuration: configuration)
        controller.onLoadStateChange = { state in print(state) }
        controller.onPageReady = { [weak controller] in print(controller?.isPageReady == true) }
        controller.host = host
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: controller)
        self.window = window
        return true
    }
}

/// 最小宿主实现验证 MWBHostDelegate 的公开协议可以从框架外遵循。
private final class ConsumerHost: MWBHostDelegate {
    func configureContainer(_ container: MWBWebViewController) {
        // 从公开模块安装容器回调，不访问框架内部展示器。
        container.onGoHome = { current in current.load(current.configuration.initialURL) }
    }
    func appInfo() -> [String: Any]? { ["appId": "mwb-consumer"] }
}

/// 固定 selector 的 Echo 插件验证公开插件基类、上下文和一次响应接口。
private final class EchoPlugin: MWBPlugin {
    @objc(mwb_echo:context:responder:)
    func echo(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        responder.success(params)
    }
}

/// 不使用 @testable，验证框架外部继承与重写入口可公开消费。
private final class ConsumerWebController: MWBWebViewController {
    override func pageDidBecomeReady() {
        // 此时状态已更新，子类无需调用 super。
        print(isPageReady)
    }
}
