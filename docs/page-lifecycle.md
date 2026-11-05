# 容器加载状态与首屏就绪

本页描述当前源码新增的能力，**已发布的 JS `0.1.1-beta.1` 和 iOS/Android `0.1.0` 不包含此能力**。使用时须同时接入包含本能力的 JS 与原生源码；仅升级 JS 不能为旧 App 增加原生实现。

每个容器分别提供 `onLoadStateChange`、`onPageReady`、只读 `loadState` 和 `isPageReady`。回调在主线程执行，没有历史重放；晚注册可读取当前状态。加载状态相同时不重复通知，连续两次整页加载如果一直处于 loading，不额外产生一次 loading 回调。

## 加载完成与首屏就绪

| 信号 | 含义 |
| --- | --- |
| idle / IDLE | 尚未开始加载 |
| loading / LOADING | 主文档正在加载 |
| loaded / LOADED | WebView 报告主文档加载完成，不保证应用渲染完成 |
| failed / FAILED | 主文档加载失败或渲染进程终止 |
| isPageReady | 当前有效主文档已经主动报告首屏就绪 |

`loaded` 与就绪相互独立：H5 可以先报告就绪，之后才收到 WebView 完成事件；完成事件不会清除就绪状态。iOS 失败原因在 `.failed(String)` 中，Android 从 `loadError` 读取，新一轮加载会清除错误。

本能力仅发送通知和保存状态。展示界面、加载指示、超时、错误页面及重试由宿主决定。主文档资源请求失败与图片等子资源失败需要区分；子资源失败不会直接把整个容器标记为失败。

## iOS：配置当前容器的闭包

```swift
let controller = MWBWebViewController(configuration: configuration)
// 在加入导航栈或访问 controller.view 之前注册，接收首次加载。
controller.onLoadStateChange = { state in
    switch state {
    case .idle: break
    case .loading: print("主文档开始加载")
    case .loaded: print("WebView 加载完成")
    case .failed(let message): print("加载失败：\(message)")
    }
}
controller.onPageReady = { [weak controller] in
    // 宿主在这里处理展示；捕获容器或拥有容器的对象时使用弱引用。
    print("当前文档已就绪：\(controller?.isPageReady == true)")
}
navigationController?.pushViewController(controller, animated: true)
```

也可以继承容器，在子类内部处理就绪：

```swift
final class WebScreenController: MWBWebViewController {
    override func pageDidBecomeReady() {
        // 库已经完成有效文档校验、去重和 isPageReady 更新，无需调用 super。
        print("当前文档首屏就绪：\(isPageReady)")
    }
}
let controller = WebScreenController(configuration: configuration)
```

内部先更新状态，再调用 `pageDidBecomeReady()`，最后调用已配置的 `onPageReady` 闭包。如果重写方法中导航或重载使文档失效，旧文档的闭包不再调用。同一项业务处理通常选择重写或闭包其中一种，避免执行两次。子类覆写 UIKit 生命周期方法时仍须调用相应 `super`，并保留库内部的 WebKit 委托和安全策略。

## Android：在首次自动加载前注册

```kotlin
class WebScreenActivity : MWBActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // super.onCreate 会创建并自动加载 WebView，因此先安装回调。
        onLoadStateChange = { state ->
            when (state) {
                MWBLoadState.IDLE -> Unit
                MWBLoadState.LOADING -> println("主文档开始加载")
                MWBLoadState.LOADED -> println("WebView 加载完成")
                MWBLoadState.FAILED -> println("加载失败：$loadError")
            }
        }
        onPageReady = {
            // 在主线程处理当前容器的展示。
            println("当前文档已就绪：$isPageReady")
        }
        super.onCreate(savedInstanceState)
    }
}
```

示例中 `Bundle` 来自 `android.os.Bundle`，MWB 类型来自 `com.mobilewebbridge`。在宿主 Manifest 注册自己的子类，并让 Intent 指向它；默认 `createIntent` 指向库内的基础 Activity：

```xml
<activity android:name=".WebScreenActivity" android:exported="false" />
```

```kotlin
// configuration 由宿主创建；此处的 this 是启动页面的 Activity。
startActivity(MWBActivity.createIntent(this, configuration)
    .setClass(this, WebScreenActivity::class.java))
```

回调在容器销毁时清除，不通过全局 MWBHost 分发。不要替换 `webView.webViewClient` 来接管加载事件，这会破坏容器自身的导航和安全处理。

## H5：主动报告首屏就绪

```ts
import { mwb, MWBBridgeError } from "mobile-web-bridge";

// 在初始路由、首屏必要数据、关键图片和初始布局准备完成后调用。
async function reportFirstScreenReady() {
  try {
    await mwb.basic.notifyPageReady();
  } catch (error) {
    if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
    else console.error(error);
  }
}
```

`mwb.notifyPageReady()` 是同一函数的根入口别名。方法无参数，返回 `Promise<GenericAsyncResult<void>>`。成功 `{errCode: 0}` 表示原生接受了本次报告，不代表宿主展示动画已完成。无需手动填写文档或容器 ID，也无需注册业务插件。

MWB 不依赖 Vue 或其他前端框架。Vue 的 `nextTick()` 只保证相应 DOM 更新，不能替代路由、业务数据或关键图片准备；动画帧等待也不能保证所有未来布局稳定。调用时机由 H5 定义，避免把首屏通知绑定到永远不会完成的后台任务。

## 周期与兼容性

- 首次加载、刷新和整页导航会撤销旧文档的就绪资格；每个新主文档可报告一次。
- 同一文档重复报告仍返回成功，但宿主只收到一次就绪通知；没有宿主监听时也保存就绪状态。
- SPA/hash 路由和容器隐藏/恢复保留当前就绪状态，不自动为每个路由建立新周期。
- 加载失败、渲染进程终止、销毁会撤销就绪资格；被拦截的跳转不会破坏仍然有效的当前文档。
- H5 未调用此方法的旧页面继续正常加载，isPageReady 保持 false；是否等待或超时降级由宿主决定。
- 通知复用文档身份校验；旧文档通知不能将新文档标记为就绪。宿主回调若立即导航，旧文档的 JS 回复可能被丢弃，调用将在 30000ms 后以 -1103 超时；超时不等于此前从未送达，不应据此重复执行业务动作。
- Android WebView 的加载回调没有导航令牌，主要按当前目标 URL 与失败终态过滤；同 URL 连续重载的迟到系统回调无法完全区分。`loaded` 只用于观察平台加载状态，首屏交接应以文档身份约束的就绪通知为准。
- Android 既有 DSBridge 通道对所有 frame 可见，documentId 用于文档生命周期隔离，不构成 iframe/XSS 安全隔离；只加载可信页面。iOS 既有网关拒绝子 frame。

| 错误 | 含义 |
| --- | --- |
| -1000 | 桥未就绪或普通浏览器环境 |
| -1006 | 当前来源不可信或尚未授权 |
| -1101 | 原生具有插件协议，但没有实现此内置方法 |
| -1102 | 调用参数或结构不合法 |
| -1103 | 30000ms 内未收到有效回复 |
| -1104 | 文档已经失效 |
| -1106 | 旧原生没有兼容网关或协议不兼容 |

不支持和普通浏览器环境都会明确失败，不会伪造首屏通知成功。
