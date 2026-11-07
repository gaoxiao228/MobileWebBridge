# Mobile Web Bridge（MWB）

Mobile Web Bridge 是一套基于 DSBridge 的移动端 Web 容器与 JavaScript SDK，帮助开发者在自己的 iOS、Android App 中快速接入 H5 页面，并让 H5 使用原生能力。

本轮目标版本为 **0.1.4**，JS、iOS、Android 与 Demo 共用源码 Tag `0.1.4`，新增 iOS 自动预热和等待绘制后转场，保留 HTML 错误页和默认 `allowedOrigins: ["*"]`；公开制品状态待核验。本文安装示例统一使用 `0.1.4`，支持 npm/Maven、源码构建、iOS Git Pod 与本地模块接入，分发状态见 [版本说明](docs/versioning.md)。

iOS 提供 Swift 编写的 `MWBWebViewController`，Android 提供 Kotlin 编写的 `MWBActivity`，H5 使用统一的 TypeScript/JavaScript API。接入方可以复用现有容器和基础能力，也可以把自己的网络、账号、支付等 App 逻辑封装成原生插件，组合到 JS SDK 中供页面调用。

## 适合用来做什么

- 在原生 App 中承载业务 H5，支持本地 HTML 和可信的线上页面。
- 让同一份 H5 调用两端的导航、设备、存储、图片等基础能力。
- 使用宿主已有的 Swift/Kotlin 服务实现业务插件，让 H5 调用 App 自己的逻辑。
- 按需组合 JS 能力、生成浏览器脚本或 npm 包，并使用统一 Demo 联调两端。

基本调用关系为：`业务 H5 → MWB-JS → DSBridge → iOS / Android 容器 → basic 或宿主业务插件`。接入方开发插件时只面对 MWB 的基类、上下文和响应器。

## 项目结构

| 项目 | 内容 | 入口 |
| --- | --- | --- |
| [MWB-JS](MWB-JS/README.md) | TypeScript SDK、插件组合构建、ESM/IIFE 和 npm 包 | `mwb` |
| [MWB-iOS](MWB-iOS/README.md) | Swift Web 容器和示例 App | `MWBWebViewController` |
| [MWB-Android](MWB-Android/README.md) | Kotlin Android library 和示例 App | `MWBActivity` |
| [MWB-Demo-Web](MWB-Demo-Web/README.md) | Vue 3 移动端测试页，覆盖 basic 和自定义原生插件示例 | `pnpm run sync:native` |

## 已有能力

当前源码的 `basic` 共 49 个公开方法：30 个既有原生桥入口、1 个通过文档网关调用的首屏就绪方法，以及 18 个 JS 句柄和事件方法。

| 能力 | 示例 |
| --- | --- |
| 容器与导航 | 打开/关闭容器、导航栏样式、右上角文字按钮及点击事件、外部浏览器 |
| 设备与应用 | 设备和应用信息、剪贴板、网络状态、拨号、权限与设置入口 |
| 媒体与文件 | 选择/压缩图片、扫码、保存图片、Base64 转换、受限文件打开 |
| 存储 | 同步分组存储、读取、删除、清空 |
| 事件与句柄 | 页面/应用生命周期、网络事件、原生调用 JS、返回键处理 |

`mwb.basic.xxx()` 与兼容入口 `mwb.xxx()` 使用相同函数和状态；原同步方法继续同步返回。各平台的支持范围、宿主配置要求和错误码见 [接口兼容表](docs/compatibility.md)。

## 加载状态与首屏就绪

当前源码支持每个容器独立配置 `onLoadStateChange`、`onPageReady` 并读取 `isPageReady`；iOS 也支持在子类中重写 `pageDidBecomeReady()`。H5 在首屏准备好后调用 `await mwb.basic.notifyPageReady()`。WebView 加载完成与 H5 首屏就绪是两个独立信号。

JS、iOS 与 Android 请配套使用 `0.1.4`，以获得完整的加载状态与首屏就绪能力。双端注册时机、H5 用法和重载边界见 [容器加载状态与首屏就绪](docs/page-lifecycle.md)。

## 接入前准备

当前源码还内置可离线使用的 HTML 错误页，支持重新加载、业务首页回调，以及接入方完整替换本地 HTML/CSS。该能力随 `0.1.4` 源码提供，接入方式见 [错误页与自定义模板](docs/error-pages.md)。

| 端 | 环境与接入方式 |
| --- | --- |
| H5 / Demo Web | Node.js 22.12+、pnpm；ESM 导入或普通 HTML 引入 IIFE |
| iOS | macOS、Xcode、CocoaPods；iOS 15+、Swift 5.9+；通过 Git Tag 或本地 Pod 接入 |
| Android | Android Studio / Android SDK 35、JDK 17；最低 API 24；通过 Maven Central 或本地 `mwb` 模块接入 |

正式仓库为 [gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。本轮 JS SDK 使用 npm 包版本 `mobile-web-bridge@0.1.4`；Android 使用 Maven 坐标 `io.github.gaoxiao228:mobile-web-bridge:0.1.4`；iOS `0.1.4` 通过同名 Git Tag 或本地 Pod 安装。各端分发状态见版本说明。

建议显式固定 `0.1.4`，不要依赖 npm 分发标签推断源码版本。完整支持范围与升级约定见 [版本兼容说明](docs/versioning.md)。文中的 `/absolute/path/to/MobileJSBridge` 请替换为实际克隆路径。

当前为预览阶段，版本变更见 [CHANGELOG](CHANGELOG.md)。

## 同步与异步调用

**MWB 支持 JS 同步调用和异步调用。basic 中的方法已定义各自的调用方式；自定义原生插件目前只支持异步 Promise。** `mwb.xxx()` 与 `mwb.basic.xxx()` 保持相同的调用方式，接入方不能在调用时随意切换。

| 类型 | 何时使用 | 返回与错误处理 |
| --- | --- | --- |
| basic 同步方法 | SDK 已提供同步入口，读取应用/设备信息或少量本地存储等需要立即返回的操作 | 直接返回值或 `void`；失败通过 `try/catch` 捕获 |
| basic 异步方法 | 导航、媒体、权限交互等 SDK 已定义为异步的操作 | 返回 `Promise<GenericAsyncResult<T>>`；使用 `await` 或 `.then/.catch` |
| 自定义原生插件方法 | App 自己的配置、网络、支付、登录等业务；包括立即读取内存的情况 | 一律使用 Promise；原生通过 responder 返回结果 |
| JS 事件与句柄方法 | 注册/解绑监听，例如 `onAppShow`、`registerHandler` | 注册通常立即返回；事件回调在后续触发，不等同于 Promise 方法 |

```ts
import { mwb, MWBBridgeError } from "mobile-web-bridge";

// 在可信 MWB 页面、桥可用之后执行；同步返回值不需要 await。
try {
  const appInfo = mwb.basic.getAppInfoSync();
  console.log(appInfo.appId);
} catch (error) {
  if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
  else console.error(error);
}

// 异步调用使用 await；成功结果在统一包装的 result 中。
async function selectPhoto() {
  try {
    const response = await mwb.basic.chooseImage({ sourceType: "album" });
    console.log(response.result);
  } catch (error) {
    console.error(error); // 用户取消、权限拒绝等也需要处理。
  }
}
```

同步方法会占用当前 JS 执行流程，不应用于等待网络、磁盘大文件、用户授权或支付结果；给同步调用加 `await` 不会把原生工作移到后台。方法的真实同步/异步性质由 SDK 和原生协议决定，不能靠增加 `Sync` 后缀或修改 TypeScript 返回类型改变。

完整同步方法清单、Promise 与事件的区别及超时边界见 [JS 调用说明](MWB-JS/README.md#同步与异步调用)。自定义插件如何立即返回数据、如何接入耗时业务，以及需要同步读取时的缓存方案，见 [插件调用方式与线程约定](docs/native-plugins.md#调用方式与线程约定)。

## H5 接入

### 从 npm 安装

在接入方的 H5 工程固定安装 npm `0.1.4`；需要自定义构建时可使用下方的源码安装方式：

```bash
# 固定本轮项目版本，避免依赖分发标签变化。
npm install mobile-web-bridge@0.1.4
```

安装 JS 包不会自动安装原生容器，仍需完成下文 iOS/Android 接入。

### 从源码构建 JS SDK

先在本项目根目录执行：

```bash
# 安装依赖并生成 ESM、类型声明及浏览器脚本。
cd MWB-JS
pnpm install
pnpm build
```

再在接入方的 H5 工程中执行：

```bash
# 需要使用自定义构建时，从本地源码安装。
npm install /absolute/path/to/MobileJSBridge/MWB-JS
```

### Vue / TypeScript / JavaScript 工程

```ts
import { mwb, MWBBridgeError } from "mobile-web-bridge";

// 在按钮点击等业务入口中调用；页面须运行于 MWB 原生容器。
async function showMessage() {
  try {
    await mwb.basic.toast({ msg: "Hello MWB" });
    mwb.basic.setStorageSync("theme", "dark"); // 同步方法无需 await。
    const theme = mwb.getStorageSync<string>("theme"); // 根兼容入口仍可用。
    console.log(theme);
  } catch (error) {
    if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
  }
}
```

异步调用成功返回 `{errCode: 0, result?: T}`；失败通过 Promise 拒绝。同步方法直接返回其声明类型，失败时抛出错误。完整用法见 [JS SDK README](MWB-JS/README.md)。

### 普通 HTML

把构建后的 `MWB-JS/dist/mwb.iife.js` 复制到网页资源目录，再于业务脚本之前加载：

```html
<!-- 默认浏览器脚本包含 basic，通过 window.mwb 使用。 -->
<script src="./mwb.iife.js"></script>
<button type="button" onclick="showMessage()">调用原生提示</button>
<script>
  // 处理桥未就绪、平台不支持等错误，避免未捕获的 Promise。
  async function showMessage() {
    try {
      await window.mwb.basic.toast({ msg: "Hello MWB" });
    } catch (error) {
      console.error(error);
    }
  }
</script>
```

普通浏览器可预览页面，但没有原生桥，无法执行原生方法。默认 SDK 只预组装 basic；使用业务插件时还需组合对应 JS 描述并构建自己的入口脚本。

## iOS 接入

### 1. 通过 CocoaPods 接入

在宿主 App 的 Podfile 对应 target 中加入，固定使用源码 Tag `0.1.4`：

```ruby
# 从 Git Tag 安装指定版本。
platform :ios, '15.0'
pod 'MobileWebBridge', :git => 'https://github.com/gaoxiao228/MobileWebBridge.git', :tag => '0.1.4'
```

iOS 暂不提供公共 CocoaPods Specs 安装。需要自定义原生实现时，也可将上面的 Git 依赖替换为本地源码依赖：

```ruby
# 使用本地源码，路径按实际位置填写。
platform :ios, '15.0'
pod 'MobileWebBridge', :path => '/absolute/path/to/MobileJSBridge/MWB-iOS'
```

在宿主工程执行 `pod install`，之后使用生成的 `.xcworkspace` 打开工程。

### 2. 创建并打开 Web 容器

以下示例在宿主已有的 `UINavigationController` 中打开页面：

```swift
import UIKit
import MobileWebBridge

// 宿主按需提供应用信息；未配置的专属能力会返回明确错误。
final class AppBridgeHost: MWBHostDelegate {
    func appInfo() -> [String: Any]? {
        ["appId": "my-app", "appVersionName": "0.1.4",
         "appVersionCode": 4, "environment": 2]
    }
}

final class HomeViewController: UIViewController {
    // controller.host 为弱引用，宿主需持有此对象。
    private let bridgeHost = AppBridgeHost()

    func openWebPage() {
        guard let url = URL(string: "https://app.example.com/start") else { return }
        let config = MWBConfiguration(
            initialURL: url,
            allowedOrigins: ["https://app.example.com"]
        )
        let controller = MWBWebViewController(configuration: config)
        controller.host = bridgeHost
        navigationController?.pushViewController(controller, animated: true)
    }
}
```

加载本地 HTML 时，将网页及依赖资源加入宿主 App 的 Copy Bundle Resources，保留相对路径，再使用 `Bundle.main.url(forResource: "index", withExtension: "html")` 作为 initialURL；仅加载包内页面时 allowedOrigins 可传空集合。两个 Demo 默认均采用本地 HTML，基础演示可离线运行，network 示例仍需网络。

按使用的能力在 Info.plist 填写相机、相册读取/写入用途说明。设备 ID、角标和原生页面等由 `MWBHostDelegate` 按需提供。更多配置见 [iOS README](MWB-iOS/README.md)。当前 iOS 源码默认自动预热一个备用 WebView，可通过 `MWBConfiguration.webViewPrewarmingEnabled` 关闭；首次未命中时正常冷启动。此优化仅适用于 iOS。当前 iOS 源码另支持 `navigateTo({ url, waitForReady: true })`，自动完成目标主文档加载与绘制准备后再转场，默认不等待，最多等待 3000ms；Android 应省略该参数，详见该接入文档。

## Android 接入

### 1. 添加 Maven 依赖

本轮 Maven 坐标为 `io.github.gaoxiao228:mobile-web-bridge:0.1.4`，在宿主工程添加以下仓库和依赖。需要修改源码或离线联调时，可使用本节后面的本地 library 模块方式，或按 [Android README](MWB-Android/README.md#maven-制品与独立接入) 构建本地 Maven 制品。

在宿主根目录的 `settings.gradle.kts` 中配置依赖仓库；已有配置时补齐缺少的仓库即可：

```kotlin
dependencyResolutionManagement {
    repositories {
        // AndroidX、Google 扫码等传递依赖来自 Google Maven。
        google()
        // MobileWebBridge 的公开制品来自 Maven Central。
        mavenCentral()
    }
}
```

在宿主 App 模块的 `app/build.gradle.kts` 中添加：

```kotlin
dependencies {
    // 固定版本；同时带入 Manifest、资源、consumer 混淆规则及传递依赖。
    implementation("io.github.gaoxiao228:mobile-web-bridge:0.1.4")
}
```

使用 Groovy DSL 的工程可在 `app/build.gradle` 的 `dependencies { ... }` 中写 `implementation 'io.github.gaoxiao228:mobile-web-bridge:0.1.4'`，仓库同样配置 `google()` 与 `mavenCentral()`。

同步 Gradle 后构建 App。宿主的 minSdk 至少为 24，构建环境使用 JDK 17；本仓库示例使用 compileSdk `35`、AGP `8.9.2`、Kotlin `2.0.21`、Gradle `8.11.1`。Maven 制品会声明 Kotlin、AppCompat 和 Google Code Scanner 等传递依赖，通常无需手动复制 AAR 或额外引入 DSBridge。扫码能力需要设备具备 Google Play 服务，完整能力差异见 [兼容表](docs/compatibility.md)。

若从本地源码切换到 Maven，请移除 `implementation(project(":mwb"))` 和仅用于 MWB 的本地 Maven 仓库配置，避免同时引入两份实现。

需要修改原生源码时，也可继续通过本地 library 模块接入。在宿主的 `settings.gradle.kts` 中加入：

```kotlin
// 将 MWB 的 library 模块映射到宿主工程。
include(":mwb")
project(":mwb").projectDir = file("/absolute/path/to/MobileJSBridge/MWB-Android/mwb")
```

随后将 App 模块中的 Maven 依赖替换为源码依赖：

```kotlin
dependencies {
    // 源码模块接入时使用此项，替换上面的 Maven 坐标。
    implementation(project(":mwb"))
}
```

源码接入同样需要宿主配置 `google()`、`mavenCentral()` 及兼容的 Android/Kotlin Gradle 插件。更多配置见 [Android README](MWB-Android/README.md)。

### 2. 安装宿主能力

在自己的 `Application.onCreate()` 中安装：

```kotlin
import android.app.Application
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBHost
import org.json.JSONObject

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // 提供 App 信息；可继续按需实现 deviceId、nativePage 等能力。
        MWB.install(object : MWBHost {
            override fun appInfo(): JSONObject = JSONObject()
                .put("appId", packageName)
                .put("appVersionName", "0.1.4")
                .put("appVersionCode", 4)
                .put("environment", 2)
        })
    }
}
```

在宿主 Manifest 的 `<application>` 中配置 `android:name=".MyApplication"`；若已有 Application，则将初始化代码合并到现有类。library 会合并 MWBActivity、FileProvider 和所需权限声明。

### 3. 从 Activity 打开页面

```kotlin
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBConfiguration

// 在宿主 Activity 的点击事件等入口执行。
val config = MWBConfiguration(
    initialUrl = "https://app.example.com/start",
    allowedOrigins = setOf("https://app.example.com")
)
startActivity(MWBActivity.createIntent(this, config))
```

加载本地 HTML 时，将页面及资源放入宿主 `app/src/main/assets/`，使用 `file:///android_asset/index.html` 作为 initialUrl，allowedOrigins 可传 `emptySet()`。Android 原生示例已包含启动即进入 H5 的写法，详见 [Android README](MWB-Android/README.md)。

## 自定义原生插件

例如 App 已有一套带登录态和签名的原生网络层，可通过 network 插件暴露给 H5：

| 端 | 接入方需要做什么 |
| --- | --- |
| iOS | 继承 `MWBPlugin`，用 `@objc(mwb_request:context:responder:)` 标记精确签名的方法，调用自己的异步服务 |
| Android | 继承 `MWBPlugin`，用 `@MWBMethod` 标记精确签名的方法，调用自己的异步服务 |
| 原生注册 | 首个容器创建前，以 `network` 名称和工厂注册；基类统一分发，无需业务 handle |
| H5 | 使用 `defineNativePlugin<Methods, Events>()({name: "network"})` 声明，再用 `createMWB({plugins: [...]})` 组合 |
| 调用 | `await mwb.network.request(params)`；通过 `mwb.network.on(...)` 订阅事件 |

注册只包含名称和工厂，不要求 version 或 methods 数组。Core 处理 JSON、超时、一次响应、取消及文档清理；子容器继承插件定义，插件实例按各自文档惰性创建。新增原生方法需要重新编译和发布 App，安装 JS 包不能代替原生接入。

两个 Demo 已实现可运行的 network 插件。完整三端代码、签名要求、错误码和生命周期见 [自定义原生插件接入](docs/native-plugins.md)。

## 运行统一 Demo

以下命令从本项目根目录开始：

```bash
# 安装 SDK 依赖；后面的同步命令会自动构建 SDK。
cd MWB-JS
pnpm install
cd ../MWB-Demo-Web
pnpm install
pnpm run sync:native
```

同步会生成 `MWB-Demo-Web/dist/`，并把同一份资源复制到 iOS 的 `Example/Resources/` 与 Android 的 `sample/src/main/assets/`。后续修改 H5 或 JS SDK 后，重新同步并构建原生 Demo。

| Demo | 启动方式 |
| --- | --- |
| iOS | 在 `MWB-iOS/Example` 执行 `pod install`，用 Xcode 打开 `MWBExample.xcworkspace`，选择 MWBExample Scheme 运行；真机需配置自己的签名团队 |
| Android | 用 Android Studio 打开 `MWB-Android`，选择 sample 运行；也可在该目录执行 `./gradlew :sample:assembleDebug` 构建 APK |
| 网页预览 | 在 `MWB-Demo-Web` 执行 `pnpm dev`，访问 `http://127.0.0.1:18743/`；普通浏览器无原生能力 |

Demo 包括 48 方法目录与调试详情、导航栏样式配置页、原生插件调试页，以及顶部白屏/MWB 可调用耗时。原生容器中的 Demo 默认开启 WebView 调试；iOS 可使用 Safari 开发菜单，Android 仅调试构建允许开启。

将 `MWB-Demo-Web/dist/` 整个目录发布到 HTTPS 静态站点，也可作为两端线上联调页。页面及同步方式详见 [Demo Web README](MWB-Demo-Web/README.md)。

## 页面来源与平台约定

- `allowedOrigins` 默认是 iOS 的 `["*"]` / Android 的 `setOf("*")`，省略该参数即可允许所有 HTTP/HTTPS 来源加载并使用原生桥，两端 Demo 同样使用此默认值。需要限制时显式传入完整来源，例如 `https://app.example.com`，不包含路径。仅完整星号有效，不支持子域名通配符；显式空集合仅允许内置本地页面。星号不放宽本地文件、其他协议或系统网络限制。业务插件的网络目标域名策略由宿主另行配置。
- Android 沿用 DSBridge 的 JavascriptInterface，桥会进入所有 frame，宿主页面不得嵌入不可信 frame。插件 documentId 用于文档生命周期隔离，不能作为防 XSS 的凭证。
- 容器默认禁用双指缩放和正文长按菜单；`navigateTo` 新容器默认隐藏导航栏，需要显示时传 `hidden: false`。导航栏支持右上角文字按钮及 JS 点击回调。
- 相机、相册、扫码等仍受系统权限和设备能力限制；Android 扫码依赖 Google Play 服务，iOS 的 `exitApp()` 返回不支持。具体差异以兼容表为准。

## 更多文档

- [JS SDK 与组合构建](MWB-JS/README.md)
- [iOS 容器与宿主配置](MWB-iOS/README.md)
- [Android 容器与宿主配置](MWB-Android/README.md)
- [统一测试页面](MWB-Demo-Web/README.md)
- [自定义原生插件接入](docs/native-plugins.md)
- [接口兼容表](docs/compatibility.md)
- [版本兼容、支持范围与升级](docs/versioning.md)
- [安全说明](SECURITY.md) · [更新记录](CHANGELOG.md)

通信底层基于 [DSBridge Android](https://github.com/wendux/DSBridge-Android) 和 [DSBridge iOS](https://github.com/wendux/DSBridge-IOS)（MIT），MWB 不依赖 Cordova。

本项目使用 [MIT 许可证](LICENSE)，第三方代码及 Demo Vue 运行时的版权和许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。分发生成脚本时应保留其许可注释及同目录的声明文件。
