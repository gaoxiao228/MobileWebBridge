import UIKit
import MobileWebBridge

// 应用启动时只注册工厂，首次网页显式调用才创建插件并发起网络请求。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private let networkService = ExampleNetworkService()
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        do {
            try MWB.registerPlugin(name: "network") { [networkService] in
                ExampleNetworkPlugin(service: networkService)
            }
        } catch { preconditionFailure("Invalid MWB plugin registration: \(error)") }
        return true
    }
}

// iOS 27 要求使用 Scene 生命周期；每个窗口在对应的 Scene 中创建。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let host = ExampleHost()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let url = Bundle.main.url(forResource: "index", withExtension: "html") else { return }

        let window = UIWindow(windowScene: windowScene)
        let configuration = MWBConfiguration(initialURL: url, allowedOrigins: [])
        let controller = ExampleWebViewController(configuration: configuration)
        controller.host = host
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.setNavigationBarHidden(true, animated: false)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }

}

// 示例宿主只显式注册 demo 页面，便于验证任意类名不会被 JS 打开。
private final class ExampleHost: MWBHostDelegate {
    func appInfo() -> [String: Any]? {
        [
            "appId": "mwb-ios-example",
            "appVersionName": "0.1.0",
            "appVersionCode": 1,
            "environment": 0
        ]
    }

    func nativePage(named name: String, extInfo: [String: Any]?) -> UIViewController? {
        guard name == "demo" else { return nil }
        let page = UIViewController()
        page.view.backgroundColor = .systemBackground
        page.title = "Native Demo"
        return page
    }
}

/// 独立的容器生命周期示例；业务 Host 不需要增加加载或就绪职责。
final class ExampleWebViewController: MWBWebViewController {
    private var readyCount = 0

    override init(configuration: MWBConfiguration) {
        super.init(configuration: configuration)
        // 初始化时视图尚未加载，可观察首次 loading；闭包弱捕获避免持有自身。
        onLoadStateChange = { [weak self] state in
            guard let self else { return }
            NSLog("[MWB-Lifecycle] loadState=%@, isPageReady=%@", String(describing: state), String(self.isPageReady))
        }
    }

    override func pageDidBecomeReady() {
        // 内部已完成文档校验、状态更新与去重，无需调用 super。
        readyCount += 1
        NSLog("[MWB-Lifecycle] pageReady count=%d", readyCount)
    }
}
