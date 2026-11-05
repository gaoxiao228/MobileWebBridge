# Mobile Web Bridge Android

Kotlin 编写的 Android Web 容器，最低 API 24。`mwb` 是可供宿主依赖的 Android library，`sample` 是本地网页示例。底层固定使用 [DSBridge Android 3.0.0](https://github.com/wendux/DSBridge-Android/tree/3.0.0) 的三个 Java 源文件（提交 `d3e5ebc6ca8170f97e420f2f482680c8e149b471`）；做了 AndroidX、Android 35 兼容、安全设置及主线程导航分发优化。

正式仓库：[gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。`io.github.gaoxiao228:mobile-web-bridge:0.1.0` 已于 2026-11-04 经维护者确认在 Central Portal 为 PUBLISHED；本机公共仓库独立消费验证仍待完成。原生默认版本 `0.1.0`，配合 JS `0.1.1-beta.1`、插件协议 1。源码 library 模块接入仍可使用。

构建将完整许可放入 AAR 的 classes.jar（META-INF/mobile-web-bridge/）；Sample assets 同时带网页/Vue/DSBridge声明，详见 THIRD_PARTY_NOTICES.md。

## 接入

将 `mwb` 模块作为 Gradle library 引入宿主项目。使用 JDK 17、Android SDK 35 和 Gradle Wrapper 构建。宿主在 `Application.onCreate` 安装应用专属能力：

```kotlin
MWB.install(object : MWBHost {
    override fun appInfo() = JSONObject().put("appId", packageName)
        .put("appVersionName", "1.0.0").put("appVersionCode", 1).put("environment", 2)
    override fun nativePage(name: String, extInfo: JSONObject?): Intent? =
        if (name == "profile") Intent(this@MyApplication, ProfileActivity::class.java) else null
})
```

从 Activity 启动容器：

```kotlin
val config = MWBConfiguration(
    initialUrl = "https://app.example.com/start",
    allowedOrigins = setOf("https://app.example.com")
)
startActivity(MWBActivity.createIntent(this, config))
```

`allowedOrigins` 需要精确写出协议、主机和可选端口。未列出的远程页面、重定向和资源会被阻止；本地 `file:///android_asset/` 可用。`http` 仅在宿主显式列出时允许。DSBridge 的 Android `JavascriptInterface` 会暴露给网页内所有 frame，所以宿主只应装载自己控制且不嵌入不可信 frame 的页面。`setEnableDebug(true)` 只在可调试应用内生效。

MWB WebView 默认禁用页面双指缩放和系统长按选项；普通点击、滚动和输入框键盘输入保持可用。此设置作用于该容器加载的所有可信 H5 页面。

宿主收到推送后可调用当前容器的 `sendEvent("remoteNotificationReceive", payload)`。Kotlin 调用 H5 句柄使用 `callJsHandler("handlerName", arrayOf(arg)) { result -> ... }`。`exitApp()` 默认仅关闭当前 MWB Activity，若宿主实现 `closeContainer()` 则由宿主自行处理。

`setNavigationBarTheme` 支持右上角文字按钮 `actionTxt`；网页传入 `onActionClick` 可接收点击事件和 `actionExt`。按钮文字跟随导航栏标题颜色，传入空 `actionTxt` 可移除按钮。图片按钮 `actionIcon` 暂不支持。
Android 导航栏标题始终按整条栏居中；返回控件显示左箭头，右侧“关闭”和操作控件只显示文字。设置 `titleColor` 时，标题、箭头和右侧文字同步变色。

扫码使用 Google Code Scanner，需要设备具备 Google Play 服务；无此服务时返回 `-1004`。此组件不提供相册扫码，显式传入 `hideAlbum: false` 返回 `-1004`。相机、旧版 Android 相册写入权限由库请求，用户拒绝返回 `-1008`。图片路径是 MWB 私有缓存目录中的文件，`convertImagePathToBase64` 和 `openFile` 不读取任意外部路径。`chooseImage` 的相机分支返回系统相机的缩略图；需要全分辨率照片时可在宿主扩展。

## 验证

```bash
./gradlew :mwb:testDebugUnitTest :mwb:assembleRelease :sample:assembleDebug
```

## Maven 制品与独立接入

Android 与 iOS、JS、Demo 共用一个仓库发布 Tag（例如 `0.1.0`），不单独创建 Android 平台 Tag。Git Tag 固定源码提交，Maven 版本由本次发布的版本表确定，详见 [共享 Tag 约定](../docs/versioning.md#多端共享-git-tag)。

公开坐标为 `io.github.gaoxiao228:mobile-web-bridge:0.1.0`。公共制品可下载后，在消费工程配置 `google()`、`mavenCentral()`，然后添加该坐标；使用者不需要维护者的 Token 或 GPG 密钥。本地联调也可以继续使用以下文件仓库流程。

```bash
# 当前目录：仅写入本机 build/maven-repository，不上传远程。
./gradlew :mwb:publishReleasePublicationToLocalIntegrationRepository

# 生成其他候选版本时，显式传入版本号。
./gradlew :mwb:publishReleasePublicationToLocalIntegrationRepository -PmwbVersion=0.1.1
```

生成 release AAR、sources、Dokka API 文档 JAR、POM 和 Gradle 元数据；POM 包含 Kotlin、AppCompat 和扫码的传递依赖。接入方在 settings 的 dependencyResolutionManagement 中配置文件仓库，再按坐标依赖：

```kotlin
repositories {
    // 替换为本次发布产生的实际路径，也可改为维护者实际提供的 Maven 仓库 URL。
    maven { url = uri("/absolute/path/to/MobileWebBridge/MWB-Android/build/maven-repository") }
    google()
    mavenCentral()
}
// app/build.gradle.kts
dependencies { implementation("io.github.gaoxiao228:mobile-web-bridge:0.1.0") }
```

在源码根目录执行 `python3 scripts/check-android-consumer.py`，自动检查 AAR/许可/sources/POM，并让独立工程仅通过坐标和 POM 编译公开 API，避免 project 依赖掩盖分发问题。脚本可加 `--offline`，此时需要依赖已缓存；它不安装或运行设备。

示例 App 启动后直接从 `android_asset` 加载网页，首页隐藏空导航栏，与 iOS 示例一致。`navigateTo` 新页面默认隐藏导航栏；传 `hidden: false` 可显示标题和返回按钮。页面源码由上级 `MWB-Demo-Web` 统一维护。更新页面或 JS SDK 后，在 `MWB-Demo-Web` 执行 `npm run sync:native`，再重新构建示例 App。SDK 方法及平台差异见 [兼容表](../docs/compatibility.md)。

## 自定义原生插件

现有 48 方法统一属于 `basic`：H5 的 `mwb.basic.navigateTo()` 与兼容的 `mwb.navigateTo()` 使用同一实现，同步存储仍是同步调用。自定义插件首版只支持异步，不会覆盖 basic。

basic 同步方法直接返回值，异步方法返回 Promise；不是每个方法都能任选同步/异步模式。自定义插件即使立即得到内存数据，仍保持 `Any? / MWBPluginCallContext / MWBPluginResponder -> Unit` 签名，通过 responder 响应，H5 使用 await；不能改成返回业务对象、Future 或 `suspend` 方法。

工厂、标记入口和 dispose 在主线程执行；网络、文件和计算交给宿主异步服务，禁止在入口用 `runBlocking` 等待。responder 可从后台完成，UI 操作仍需回主线程。完整的立即响应示例、H5 缓存方案、错误与取消处理见 [插件调用方式与线程约定](../docs/native-plugins.md#调用方式与线程约定)，同步方法清单见 [JS 调用说明](../MWB-JS/README.md#同步与异步调用)。

在创建第一个容器前（通常在 `Application.onCreate`）仅注册名称和工厂，无需 `version`、`methods` 数组或业务分发 `when`：

```kotlin
import com.mobilewebbridge.plugins.MWBMethod
import com.mobilewebbridge.plugins.MWBPlugin
import com.mobilewebbridge.plugins.MWBPluginCallContext
import com.mobilewebbridge.plugins.MWBPluginResponder

// 共享宿主服务由工厂闭包注入；每个活动文档惰性创建自己的插件实例。
MWB.registerPlugin(name = "network") { NetworkPlugin(appNetworkService) }

class NetworkPlugin(private val service: AppNetworkService) : MWBPlugin() {
    @MWBMethod
    fun request(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        // 耗时任务交给宿主异步服务，入口和 dispose 均在主线程执行。
        val cancel = service.request(params) { result ->
            responder.success(result)
            context.emit("requestFinished", result)
        }
        context.onCancel(cancel)
    }

    override fun dispose() {
        // 在这里释放当前文档的观察器；普通隐藏、前后台和 SPA hash 不触发清理。
    }
}
```

`AppNetworkService` 是宿主自行提供的业务服务；可直接参考 Sample 的 `NetworkService`、`NetworkPlugin`、`HostNetworkService` 完整实现。新增业务方法只需添加 `@MWBMethod` 和对应 H5 类型，再重新发布 App。插件不会直接注册到 DSBridge。

业务方法必须是公开实例方法、返回 `Unit`，参数精确为 `Any?`、`MWBPluginCallContext`、`MWBPluginResponder`；未注解辅助方法不开放。错误签名、同名重载冲突属于配置错误（`-1105`），未知方法返回 `-1101`。consumer rules 随 AAR 发布，保留运行时注解、业务方法名称/签名与反射基类边界。

JSON 支持 null、布尔、有限数值、字符串、`JSONObject`/`JSONArray`、字符串键 `Map` 和 `List`。循环、非有限数字或任意原生对象返回 `-1102`。省略参数按 JSON null 传入；`success()` 省略 result，`success(null)` 保留 `result: null`。响应器允许从后台线程调用并保证一次完成。默认超时 30000ms，允许 1..120000ms，包含工厂创建时间；超时、主文档导航、销毁调用 `onCancel`，丢弃晚到结果。`context.activity` 仅在当前可信文档有效时提供可空 Activity，业务不应长期持有它。

注册表在首个容器创建时冻结，拒绝后续注册或重名；子容器继承同一份不可变定义，但插件实例独立。插件名、方法名、事件名采用 `[a-z][a-zA-Z0-9_]*`；插件名不能占用 basic、version、48 个根方法或 Core 成员；业务方法和事件避开 on/then/catch/finally/toJSON/inspect/constructor/prototype/__proto__。事件只投递到发起调用的当前可信文档，不缓存或跨容器广播。

内部 wire 使用同步 `mwb.pluginSession` 获取 `{protocol:1,documentId}`，异步 `mwb.pluginInfo`、`mwb.invokePlugin` 校验同一身份，原生事件走 `mwb.pluginEvent`。这些入口由 SDK 管理，宿主无需手写调用。文档令牌不能隔离同源脚本或防止 XSS，来源与 frame 安全边界沿用前文说明。桥错误为 `-1006` 不可信、`-1100` 缺插件、`-1101` 缺方法、`-1102` 参数/JSON 错误、`-1103` 超时、`-1104` 文档失效、`-1105` 插件异常、`-1106` 协议不兼容。

Sample 注册 `network`：请求 `{url,method:"GET"|"POST",headers?:Record<string,string>,body?:string}`，响应 `{status,headers,body}`，事件 `requestFinished` 携带 `{url,status}`。仅允许 HTTPS 的 example.com、httpbin.org，禁止 URL 用户信息、非标准端口、自动重定向和 GET body，限制文本请求/响应为 1MiB，支持取消。初始化不外发请求，需在插件调试页输入地址并显式点击。HTTP 非 2xx 状态属于成功返回的业务数据；传输失败使用业务错误码 1001。示例网络不是 SDK 内置插件，生产中请注入宿主现有客户端及自己的域名策略。

扩展验证（不安装设备）：

```bash
./gradlew :mwb:testDebugUnitTest :mwb:assembleRelease :sample:testDebugUnitTest :sample:assembleDebug :sample:assembleRelease
```

Sample release 开启消费端 R8，可检查 `sample/build/outputs/mapping/release/mapping.txt` 与 APK 内方法签名/运行时注解。Robolectric 及构建不等于真机验收；实际网络、WebView 脚本与前后台行为仍需宿主设备测试。

## 加载状态与首屏就绪

当前源码新增容器级 `onLoadStateChange`、`onPageReady` 和只读 `isPageReady`。已发布的 JS `0.1.1-beta.1` 与原生 `0.1.0` 不包含此能力；须同时接入含本能力的 JS 与原生源码。WebView 完成不代表 H5 首屏准备完成，H5 应在合适时机调用 `mwb.basic.notifyPageReady()`。

Android 在子类的 `super.onCreate` 前安装回调，并让宿主 Manifest/Intent 指向该子类；失败原因通过 `loadError` 读取。

[SampleWebActivity](sample/src/main/java/com/mobilewebbridge/sample/SampleActivity.kt) 演示加载与就绪闭包的注册，结果记录在 `MWB-Lifecycle` 日志中。H5 Demo 不自动发送就绪通知，也不提供相关操作入口；接入方应由自己的业务页面在关键内容呈现后报告。

双端代码示例、就绪去重、重载与兼容性见 [容器加载状态与首屏就绪](../docs/page-lifecycle.md)。
