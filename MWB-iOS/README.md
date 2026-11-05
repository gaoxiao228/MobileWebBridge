# Mobile Web Bridge iOS

Swift 编写的 Web 容器，底层使用 DSBridge 3.0.6。最低系统版本为 iOS 15。为适配现代 Xcode，仓库在 `Vendor/DSBridge` 固定保存上游 3.0.6 源码，来源提交为 `f0e3c724dd362800528f8b6c788bdad7006cc187`。

## 接入

正式仓库：[gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。当前原生版本 `0.1.0`，配合 JS `0.1.1-beta.1` 和插件协议 1；未发布 CocoaPods Specs。

仓库根目录提供单仓库 Podspec。使用 Git 接入时固定源码 Tag：

```ruby
# 固定共享源码版本，避免跟随分支变化。
pod 'MobileWebBridge', :git => 'https://github.com/gaoxiao228/MobileWebBridge.git', :tag => '0.1.1'
```

源码 Tag `0.1.1` 包含根 Podspec。它是仓库源码版本，不代表发布新的 CocoaPods Specs。需要修改源码或离线开发时，可使用本目录的本地 CocoaPods 接入：

```ruby
pod 'MobileWebBridge', :path => '/absolute/path/to/MWB-iOS'
```

宿主创建 `MWBConfiguration(initialURL:allowedOrigins:)`，然后将 `MWBWebViewController` 放入自己的导航栈。`allowedOrigins` 使用完整来源（例如 `https://app.example.com`），不包含路径；未列出的远程页面和重定向会被拦截。App 包内的本地文件可直接加载。

容器会为每个页面设置不可缩放的 viewport，并关闭长按文字菜单和链接预览；输入框仍可正常输入与选中文字。这个行为也适用于宿主加载的可信线上 H5 页面。

应用信息、设备 ID、角标和原生页面由 `MWBHostDelegate` 提供。宿主只需实现实际使用的回调，未实现的方法会返回“未配置”错误。`openNativePage` 只能进入宿主按名称显式返回的页面。宿主收到推送后可调用 `controller.sendEvent("remoteNotificationReceive", data: payload)`。

宿主需在 Info.plist 中按使用的能力填写 `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription` 和 `NSPhotoLibraryAddUsageDescription`。示例工程已配置。iOS 的 `exitApp()` 保留 JS 方法，但返回不支持，不会结束进程。
`setNavigationBarTheme` 支持标题、颜色、显示/隐藏及右上角文字按钮（`actionTxt`）。设置 `actionExt` 和 `onActionClick` 后，点击按钮会将 `actionExt` 传给当前页面的 JS 回调；空 `actionTxt` 会移除按钮。`actionIcon` 和状态栏等未实现字段返回 `-1004`。

## 本地示例

```bash
cd Example
pod install
xcodebuild -workspace MWBExample.xcworkspace -scheme MWBExample -destination 'generic/platform=iOS' build-for-testing CODE_SIGNING_ALLOWED=NO
```

示例应用加载内置网页，首页隐藏空导航栏。`navigateTo` 新页面默认隐藏导航栏；传 `hidden: false` 可显示标题和返回按钮。在导航栈内，即使导航栏隐藏，也支持从屏幕左边缘向右滑返回；根页面不触发返回，交互转场期间不重复启动。系统手势直接执行原生返回，不等待异步 JS 返回键处理器；需要拦截的交互请使用页面返回按钮。页面源码由上级 `MWB-Demo-Web` 统一维护；更新页面或 JS SDK 后，在 `MWB-Demo-Web` 执行 `npm run sync:native`，再重新构建 Xcode 示例。项目公开方法及平台差异见上级 `docs` 中的兼容表。

## 真机运行

用 Xcode 打开 `Example/MWBExample.xcworkspace`，选择 `MWBExample` Scheme 和已连接的 iPhone。在 Demo App 的 Signing & Capabilities 中选择自己的开发团队，再运行。示例工程默认允许真机代码签名；首次使用免费 Apple ID 安装时，按手机提示信任该开发者。免费签名的描述文件到期后，需要在 Xcode 中重新签名安装。

## 依赖说明

上游 DSBridge 3.0.6 使用部分已弃用的 UIKit API，编译可能出现来自上游源码的警告。Podspec 已使用正式仓库。

SDK 隐私清单通过 `MobileWebBridgePrivacy.bundle` 分发，声明存储包装和插件超时计时的必要原因；宿主仍需申报业务及其他依赖的数据用途。SDK 不自行追踪用户或收集用户数据；宿主应根据业务、网页和其他依赖的实际用途填写 App 隐私信息。

LICENSE 包含本项目及 DSBridge 的完整许可声明，用于 CocoaPods Acknowledgements；THIRD_PARTY_NOTICES.md 同时随 Pod 保留。Demo 的签名团队由运行者自行选择，网页资源中的两份许可文本随 Bundle 打包。源码根目录可运行 `node scripts/check-ios-consumer.mjs`，从框架外验证全新宿主的安装和无签名编译。

## 自定义原生插件

basic 同时支持同步与异步方法：同步方法直接返回值，异步方法返回 Promise。继承 `MWBPlugin` 的业务方法当前只支持异步；即使立即读到内存配置，也应保持 `Any? / MWBPluginCallContext / MWBPluginResponder -> Void` 签名，通过 responder 返回，H5 使用 await。不要把 selector 改成普通同步返回或 Swift `async` 方法，也不要用信号量把异步服务包装成同步调用。

工厂、业务入口和 dispose 在主线程执行；网络、文件和计算任务由宿主异步服务执行，UI 操作仍在主线程。完整的立即响应示例、H5 缓存方案、错误与取消处理见 [插件调用方式与线程约定](../docs/native-plugins.md#调用方式与线程约定)，basic 的同步方法清单见 [JS 调用说明](../MWB-JS/README.md#同步与异步调用)。

宿主在第一个容器创建前调用 `try MWB.registerPlugin(name:factory:)`，只提供名字和工厂；不配置 version、methods 或 handle。第一个容器取得快照后注册表锁定；非法名称、重名、覆盖 basic/Core/48 个兼容成员均抛出原生配置错误。`navigateTo` 子容器继承定义快照，但按各自活动主文档惰性创建独立插件实例。共享服务通过工厂闭包注入。

```swift
// App 启动时注册；已有宿主服务由业务方提供。
try MWB.registerPlugin(name: "network") {
    NetworkPlugin(service: appNetworkService)
}

final class NetworkPlugin: MWBPlugin {
    // 省略 service 的存储和初始化；固定 selector 就是方法标记。
    @objc(mwb_request:context:responder:)
    func request(_ params: Any?, context: MWBPluginCallContext,
                 responder: MWBPluginResponder) {
        // 校验业务参数后转交宿主异步服务，不在主线程阻塞。
        let task = service.request(params) { result in
            responder.success(result) // 可从任意线程完成；重复响应自动忽略。
            context.emit("requestFinished", data: ["url": "https://example.com", "status": 200])
        }
        context.onCancel { task.cancel() }
    }

    override func dispose() {
        // 主文档替换或容器销毁时释放本插件持有的观察器等资源。
    }
}
```

业务方法必须精确使用 `Any? / MWBPluginCallContext / MWBPluginResponder` 三个参数和 `Void` 返回值，selector 必须为 `mwb_方法名:context:responder:`。Core 自动扫描并缓存标记方法，拒绝错误 selector、参数数目、非对象 ABI、非 Void 返回和继承冲突；普通辅助方法与 NSObject 成员不对 H5 暴露。Swift 的 Objective-C 方法编码不保留对象的具体 Swift 类，所以 Core **无法自动识别**“同为对象 ABI 但具体类错误”的签名（如把 params 声明为 String）；这类实现不受支持，需由原生作者遵守上述精确签名。Swift fatalError/precondition/cast trap 也不是可恢复异常。可抛出的 Swift 工厂错误和 Objective-C 插件异常会转为 `-1105`。

`MWBPluginCallContext` 提供只读 `containerId/documentId/pageURL`、弱引用 `controller`、`emit(_:data:)` 和 `onCancel(_:)`。Context 只能向自己的插件和当前文档发事件；名字采用 `[a-z][a-zA-Z0-9_]*`，禁止 `on/then/catch/finally/toJSON/inspect/constructor/prototype/__proto__`。参数、结果及事件只接受 JSON；`success()` 省略 result，`success(NSNull())` 保留显式 null。

新插件只支持异步调用，默认 30000ms，可传 1..120000 的整数 timeoutMs。超时包含工厂创建；超时或换页会取消 pending，旧结果和事件不会进入新文档。主文档 `atDocumentStart` 同步建立原生身份，不等待 `didFinish`；DSBridge prompt 的真实 WKFrameInfo 用于拒绝 iframe。新增回复和事件的 JavaScript 在实际执行时再次核对身份，避免旧回调排队后重名进入新页面。该传输适配当前固定 DSBridge 3.0.6 的 `dscbN` 回调及 `_dsf` 同步注册表；未来升级 DSBridge 时需一起核对。隐藏、打开子容器和 SPA/hash 路由保留实例；整页导航、进程终止和销毁撤销实例。

H5 需同时接入原生插件描述：

```ts
// 接入方编译自己的浏览器入口；默认 SDK 仍只包含 basic。
const network = defineNativePlugin<NetworkMethods, NetworkEvents>()({ name: "network" });
const mwb = createMWB({ plugins: [network] });
const available = await mwb.hasPlugin("network"); // 查询不创建实例。
const off = mwb.network.on("requestFinished", event => console.log(event));
await mwb.network.request({ url: "https://example.com", method: "GET" });
off(); // 页面卸载时清理订阅。
```

`hasPlugin("basic")` 恒为 true；该查询不保证每个业务方法存在，不提供 hasMethod。48 个 basic 方法与兼容根入口保持原有同步/异步性质。原生改动需要重新发布 App；安装 npm 包不能代替原生接入。旧 App 没有插件网关时 H5 明确拒绝为 `-1106`。

wire 固定为同步 `mwb.pluginSession`、异步 `mwb.pluginInfo` 与 `mwb.invokePlugin`；协议 1 携带原生 documentId，调用另含 plugin/method/params/callId/timeoutMs。事件通过 `mwb.pluginEvent` 的单个消息 `{documentId,plugin,name,data}` 分发。新增错误码为 `-1100` 插件缺失、`-1101` 方法不支持、`-1102` 参数/JSON 非法、`-1103` 超时、`-1104` 文档失效、`-1105` 插件异常、`-1106` 协议不兼容；不可信来源仍为 `-1006`。

Example 的 `NetworkPlugin.swift` 是宿主业务示例，不是 basic 内置网络能力。其工厂注入宿主 URLSession 服务，仅允许精确域名 `example.com` 和 `httpbin.org` 的 HTTPS GET/POST，重定向继续校验域名、HTTPS 和默认 443 端口。请求使用字符串 headers，body 仅 POST 可传字符串（GET 带 body 返回 -1102），响应为 `{status,headers,body}`；UTF-8 文本响应流式限制 1 MiB，POST body 同样限制 1 MiB。HTTP 非 2xx 仍作为网络响应返回，网络/超限失败使用业务错误 1001；完成事件为 `requestFinished: {url,status}`。服务支持取消，启动和能力查询都不会发出请求。首页进入原生插件调试页后，填入 URL 并显式点击执行；子容器可以打开同一调试页验证继承。

## 插件验证

```bash
# macOS 原生可执行检查：真实插件 Core、JavaScriptCore 执行时守卫、URLSession 假传输。
./Tests/PluginContract/run.sh

# 编译 Example 及已有 XCTest；不创建或启动模拟器。
cd Example
pod install
xcodebuild -workspace MWBExample.xcworkspace -scheme MWBExample \
  -destination 'generic/platform=iOS' build-for-testing CODE_SIGNING_ALLOWED=NO
```

`build-for-testing` 只编译 XCTest，不表示已在设备执行测试；主文档首屏时序、真实 WebView/网络和前后台行为仍需宿主的设备验收。本次不发布 Pod；发布前还需验证远程 Tag、宿主权限及业务域名配置。

## 加载状态与首屏就绪

当前源码新增容器级 `onLoadStateChange`、`onPageReady` 和只读 `isPageReady`。已发布的 JS `0.1.1-beta.1` 与原生 `0.1.0` 不包含此能力；须同时接入含本能力的 JS 与原生源码。WebView 完成不代表 H5 首屏准备完成，H5 应在合适时机调用 `mwb.basic.notifyPageReady()`。

iOS 在加载视图前注册闭包；也可继承容器并重写 `pageDidBecomeReady()`，无需调用 super。

示例 App 的 [ExampleWebViewController](Example/AppDelegate.swift) 演示加载回调注册及就绪方法重写，结果记录在 `MWB-Lifecycle` 日志中。H5 Demo 不自动发送就绪通知，也不提供相关操作入口；接入方应由自己的业务页面在关键内容呈现后报告。

双端代码示例、就绪去重、重载与兼容性见 [容器加载状态与首屏就绪](../docs/page-lifecycle.md)。
