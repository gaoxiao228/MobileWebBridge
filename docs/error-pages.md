# 页面加载失败与自定义错误页

本页说明 `0.1.3` 提供的能力，Android Maven 制品已公开，iOS 可通过同名 Git Tag 接入。旧版本 iOS `0.1.0`、Android `0.1.1` 不包含这项功能；需要接入配套原生 SDK。只升级 JS SDK 不能为旧 App 增加错误页。

容器默认提供本地 HTML 错误页和“重新加载”按钮。配置首页回调后显示“回到首页”，具体回 Web 首页、切换原生 Tab 或关闭当前容器，由宿主决定。错误页使用独立普通 WebView，不改变业务 WebView 的浏览历史，不需要业务 JS SDK，也没有业务插件权限。

## 触发范围与恢复

- 主文档网络失败、系统请求超时、HTTP >= 400、TLS 证书失败、本地入口读取失败和渲染进程终止会显示错误页。
- 首次入口被来源策略拒绝也会显示提示，但不允许重试不可信地址。已有有效页面拒绝不可信导航时保留当前页面。
- 图片、CSS、脚本等子资源失败、业务 fetch/XHR 错误、JS 异常和正常导航取消不会覆盖整页。
- 不以 `notifyPageReady()` 是否调用判断加载超时，不自动重试或在网络恢复后自动刷新。
- 重新加载只重试已确认的 GET 地址，继续应用来源与证书校验；POST 和未知方法不自动重发，避免重复业务提交。
- 重试期间错误页保留并禁用重试按钮，首页入口仍可用；主文档 `loaded` 后关闭，不等待 H5 首屏就绪。失败则恢复按钮。
- 错误 HTML 无法读取、协议初始化失败或 5 秒未完成、错误 WebView 进程异常时，转为原生简易界面。自定义脚本或样式自身的缺陷不保证能自动识别。

Android 的错误重试使用新建业务 WebView，普通失败时通过平台 saveState/restoreState 保留历史。渲染进程已经终止时只能使用最近一次成功页面的历史快照；内存中的网页状态、表单输入和 JS 变量不保证恢复。iOS 通过原生导航身份隔离旧回调并重新请求失败地址。

## iOS：配置首页回调

```swift
import MobileWebBridge

// 在视图首次加载前设置回调，仅作用于这个容器实例。
let controller = MWBWebViewController(configuration: configuration)
controller.onGoHome = { current in
    // 也可以在这里执行原生首页导航。
    current.load(homeURL)
}
```

需要内部 `navigateTo` 创建的子容器也支持首页时，使用宿主初始化钩子：

```swift
final class AppHost: MWBHostDelegate {
    let homeURL: URL
    init(homeURL: URL) { self.homeURL = homeURL }

    func configureContainer(_ container: MWBWebViewController) {
        // 使用回调参数中的当前容器，不捕获父页面；homeURL 是配置数据。
        let home = homeURL
        container.onGoHome = { current in current.load(home) }
    }
}

// 宿主需要由 App 强持有；容器 host 为弱引用。
let host = AppHost(homeURL: homeURL)
let controller = MWBWebViewController(configuration: configuration)
controller.host = host
```

`configureContainer` 在每个实例首次业务加载前调用一次，子容器沿用宿主。未配置 `onGoHome` 时按钮隐藏，SDK 不擅自导航。不要在初始化钩子中提前调用 load；在钩子内配置回调即可。

## Android：配置首页回调

```kotlin
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBHost

class AppHost : MWBHost {
    override fun configureContainer(container: MWBActivity) {
        // 每个容器及重建后的实例都会安装自己的回调，不通过 Intent 序列化函数。
        container.onGoHome = { current -> current.load("https://app.example.test/") }
    }
}

// 在 Application.onCreate 中安装，使进程重建后也能重新获得宿主配置。
MWB.install(AppHost())
```

也可以在自己的 Activity 子类中设置单实例 `onGoHome`。需要接收首次加载前的初始化时，在 `super.onCreate` 前设置；统一宿主钩子会随后执行，不要重复覆盖同一回调。

## 替换为自己的 HTML/CSS

建议准备一个目录，例如 `custom-error/`，包含入口 HTML 和相对引用的 CSS、JS、图片、字体。所有资源随 App 打包，不接受远程错误页 URL 或任意磁盘路径。

iOS：将目录作为文件夹资源复制进 App，或放入单独资源 Bundle，保留相对目录结构：

```swift
// Bundle 可以是 .main 或宿主提供的独立资源 Bundle。
let configuration = MWBConfiguration(
    initialURL: initialURL,
    allowedOrigins: allowedOrigins,
    errorPage: .init(source: .bundled(
        bundle: .main, directory: "custom-error", entry: "index.html"
    ))
)
```

Android：将目录放到 App 的 `src/main/assets/custom-error/`：

```kotlin
// assetDirectory 是 assets 内的相对目录，null 使用 SDK 默认模板。
val configuration = MWBConfiguration(
    initialUrl = initialUrl,
    allowedOrigins = allowedOrigins,
    errorPage = MWBErrorPageConfiguration(assetDirectory = "custom-error")
)
```

自定义 HTML 不要求固定布局、类名或按钮 ID。主文档完成后原生注入专用接口，页面监听就绪与状态更新：

```javascript
// 在错误 HTML 自己的脚本中执行，不要引入业务 mwb.iife.js。
function renderError() {
  const state = window.mwbErrorPage?.context;
  if (!state) return;
  document.querySelector('.message').textContent = state.message;
  const retry = document.querySelector('.retry');
  retry.disabled = !state.canRetry || state.isRetrying;
  retry.textContent = state.isRetrying ? '正在重新加载…' : '重新加载';
  document.querySelector('.home').hidden = !state.canGoHome;
}

window.addEventListener('mwb-error-ready', renderError);
window.addEventListener('mwb-error-state-change', renderError);
document.querySelector('.retry').addEventListener('click', () => window.mwbErrorPage?.retry());
document.querySelector('.home').addEventListener('click', () => window.mwbErrorPage?.goHome());
// 同时兼容脚本晚于协议初始化的情况。
renderError();
```

`context` 为只读状态快照：

| 字段 | 含义 |
| --- | --- |
| `version` | 当前为 `1` |
| `kind` | `network`、`timeout`、`http`、`tls`、`localResource`、`rendererTerminated`、`blockedNavigation` |
| `message` | 适合向用户展示的说明，使用文本方式渲染 |
| `httpStatus` | HTTP 错误状态码，其余情况为 null |
| `canRetry` | 原生是否允许自动重试当前请求 |
| `canGoHome` | 当前容器是否配置首页回调 |
| `isRetrying` | 是否正在重试 |

原生始终再次校验动作资格，修改 JS 对象不能开放额外能力。错误页不接收完整失败 URL、Cookie、请求头或原始系统异常，不允许联网、iframe、弹窗、表单导航、目录越界或读取其他本地文件。打包的自定义脚本属于 App 自身代码，仍需接入方保证模板正确。

原生可以读取 `errorPageError` 获取失败 URL、方法、类型、HTTP 状态和诊断信息；iOS 仍可从 `.failed(String)` 读取原因，Android 仍保留 `loadError`。不要将可能含敏感参数的诊断 URL 直接显示给用户。

## 完全由宿主展示

```swift
// 禁用内置展示不会禁用失败通知。
let errorPage = MWBErrorPageConfiguration(enabled: false)
```

```kotlin
// 配置传给 MWBConfiguration，宿主继续观察 onLoadStateChange。
val errorPage = MWBErrorPageConfiguration(enabled = false)
```

两端 Demo 首页不展示专门的错误页入口。可在 `navigateTo` 方法详情中填写同目录下不存在的页面地址以触发默认错误页；自定义模板可参考上面的示例，在原生创建容器时通过 `errorPage` 配置使用。示例首页回调选择重新装载本地首页；真实 App 可以替换为自己的导航。
