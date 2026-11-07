# 自定义原生插件接入

接入方分别实现 iOS、Android 的业务插件，再在 H5 组合有类型的 JS 描述。MWB 负责统一分发、结果、事件、超时和文档生命周期；宿主继续负责自己的网络、支付、登录态及业务权限。注册只有插件名和工厂，没有 version、methods 数组，也不需要业务方实现 handle。

当前源码 49 方法属于 basic（已发布版本为 48），`mwb.basic.xxx()` 与 `mwb.xxx()` 共用函数和状态。业务插件只挂载到自己的命名空间，不覆盖根入口。以下用两个 Demo 已实现的 network 为例；支付插件使用相同机制，但真实支付 SDK、订单校验和结果确认由接入方实现。

## 调用方式与线程约定

MWB 的 basic 同时包含同步、异步方法；**继承 `MWBPlugin` 的自定义业务方法当前只支持异步**。底层 DSBridge 能提供同步传输，并不代表 MWB 已开放业务插件同步入口。`pluginSession` 的内部同步握手也不是接入方的业务扩展点。

| 业务场景 | 当前插件应如何实现 |
| --- | --- |
| 读取内存中的配置、已缓存的状态 | 入口中立即调用 `responder.success`，H5 仍然 await Promise |
| 网络、支付、登录授权、文件读写或图片处理 | 启动宿主异步服务，完成时通过 responder 响应，登记可用的取消句柄 |
| H5 渲染过程中需要同步读一个值 | 先异步获取快照并保存在 H5，再从 JS 内存同步读取；这不是同步跨桥 |
| 希望新增与 basic 的 `getAppInfoSync` 一样的同步原生方法 | 当前公开插件协议不支持；不要修改声明或直接注册 DSBridge 来绕过 Core |

只有 SDK 已提供的同步方法才能按同步方式跨桥调用。同步场景应能立即完成，不等待网络、用户操作或其他异步回调；同步桥会阻塞 JS 执行，等待主线程任务还可能形成死锁。耗时或完成时间不确定的工作使用异步。

### 原生立即得到结果，H5 仍然异步获取

以下是最小可用的 `appConfig.getSnapshot` 业务插件。配置由宿主预先准备，插件不做网络请求，也不读取磁盘；Swift/Kotlin 分别加入宿主源码，并在首个 MWB 容器创建前注册。

```swift
import Foundation
import MobileWebBridge

// 仅传入可序列化的非敏感配置；此示例保存初始化时的快照。
final class AppConfigPlugin: MWBPlugin {
    private let snapshot: [String: Any]

    init(snapshot: [String: Any]) {
        self.snapshot = snapshot
        super.init()
    }

    @objc(mwb_getSnapshot:context:responder:)
    func getSnapshot(_ params: Any?, context: MWBPluginCallContext,
                     responder: MWBPluginResponder) {
        responder.success(snapshot) // 立即响应，原生返回值仍为 Void。
    }
}

// 放到 App 初始化流程，在首个容器创建前执行并处理注册错误。
try MWB.registerPlugin(name: "appConfig") {
    AppConfigPlugin(snapshot: ["theme": "light", "featureEnabled": true])
}
```

```kotlin
import com.mobilewebbridge.MWB
import com.mobilewebbridge.plugins.MWBMethod
import com.mobilewebbridge.plugins.MWBPlugin
import com.mobilewebbridge.plugins.MWBPluginCallContext
import com.mobilewebbridge.plugins.MWBPluginResponder

// Map 中的值仍须满足 JSON 契约；原生返回值为 Unit，不直接 return snapshot。
class AppConfigPlugin(private val snapshot: Map<String, Any?>) : MWBPlugin() {
    @MWBMethod
    fun getSnapshot(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        responder.success(snapshot)
    }
}

// 放到 Application.onCreate，在首个容器创建前注册。
MWB.registerPlugin(name = "appConfig") {
    AppConfigPlugin(mapOf("theme" to "light", "featureEnabled" to true))
}
```

```ts
import { createMWB, defineNativePlugin, MWBBridgeError,
         type GenericAsyncResult } from "mobile-web-bridge";

type AppConfig = { theme: string; featureEnabled: boolean };
interface AppConfigMethods {
  // 无参调用传给原生的是 null；不能把返回类型改为 AppConfig。
  getSnapshot(): Promise<GenericAsyncResult<AppConfig>>;
}
const appConfig = defineNativePlugin<AppConfigMethods>()({ name: "appConfig" });
const sdk = createMWB({ plugins: [appConfig] });
let cachedConfig: AppConfig | undefined;

// 在可信容器内、桥可用后调用；完成前展示加载态或采用明确的默认配置。
async function initializeConfig(): Promise<void> {
  try {
    const response = await sdk.appConfig.getSnapshot();
    cachedConfig = response.result;
  } catch (error) {
    if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
    else console.error(error);
  }
}

// 只同步读取 JS 内存：初始化前返回 undefined，不产生新的原生调用。
function readCachedConfig(): AppConfig | undefined {
  return cachedConfig;
}
```

该缓存不是原生实时状态。配置或账号变化后需由业务重新获取或订阅插件事件更新，退出账号时清理用户相关缓存；不要把支付最终结果或实时权限状态长期缓存后当作权威值。示例的原生快照固定于初始化时，动态配置应改为注入宿主服务并提供刷新/事件契约。

### 耗时业务的完成、错误与取消

两端的插件入口、工厂和 `dispose` 在主线程执行。**异步桥不等于 MWB 自动把业务代码放到后台**；不要在入口或工厂里同步请求网络、大量计算、用信号量等待、`Thread.sleep`、Kotlin `runBlocking` 等。由宿主的 URLSession、网络客户端、线程池或协程承担耗时工作；UIKit/Android UI 操作仍回到主线程。

- Swift 入口必须返回 `Void`，Kotlin 必须返回 `Unit`；结果通过 `responder.success(value)` 或 `responder.failure(code, message)` 完成，不能把 Swift `async` / Kotlin `suspend` 直接作为标记方法签名。
- 可以从服务的完成回调或后台线程调用 responder；每个参数错误、成功、失败和用户取消分支都要明确完成一次，Core 会忽略重复响应。调用结束并不自动结束宿主自行创建的任务。
- 有可取消任务时，用 `context.onCancel` 登记取消操作，并在 `dispose` 释放文档范围资源。超时、整页导航和销毁会触发相应清理，暂时隐藏或 SPA 路由不等于销毁。
- JS/原生插件超时默认为 30000ms，可配置 1..120000ms，包含工厂创建时间；它不能抢占阻塞主线程的业务代码。超时不代表支付等实际业务已撤销，宿主需根据订单号查询最终状态并保证幂等。
- Promise 成功保留 `{errCode: 0, result?: T}` 包装；失败拒绝为 `MWBBridgeError`，H5 必须 catch。参数、结果和事件都须满足 JSON 契约，函数不能作为普通业务参数跨桥传递。

下面的 network 三端示例演示耗时业务的入口和调用；可运行的完整异步服务见 [iOS 示例](../MWB-iOS/Example/NetworkPlugin.swift) 和 [Android 示例](../MWB-Android/sample/src/main/java/com/mobilewebbridge/sample/NetworkPlugin.kt)。basic 的同步清单、Promise 与事件的区别及其尚无统一超时的限制，见 [JS 调用说明](../MWB-JS/README.md#同步与异步调用)。

## 1. 先确定三端业务契约

| 项目 | network 示例约定 |
| --- | --- |
| 插件名 | `network` |
| 方法 | `request` |
| 参数 | `{url, method: "GET" | "POST", headers?: Record<string,string>, body?: string}` |
| 结果 | `{status: number, headers: Record<string,string>, body: string}` |
| 事件 | `requestFinished: {url: string, status: number}` |

方法参数只传一个 JSON 值，省略按 null 处理；只能传有限数值、布尔、字符串、null、数组和字符串键对象。不要跨桥传函数、原生实例、循环或 getter。业务类型由接入方维护，MWB 不从 TypeScript 自动生成原生方法。

成功结果保留统一包装 `{errCode: 0, result?: T}`，不会自动解包。失败通过 `MWBBridgeError` 拒绝，携带 `errCode/errorMsg`。HTTP 404/500 等是请求结果中的 status；示例的网络传输失败为业务错误 1001。

## 2. iOS：继承、标记、注册

先通过本地 Pod 接入 `MobileWebBridge`，配置容器及可信页面，见 [iOS README](../MWB-iOS/README.md)。可直接参考 `Example/NetworkPlugin.swift` 的完整插件与 URLSession 服务：

```swift
import MobileWebBridge

// 应用初始化时注册；必须在创建第一个 MWB 容器之前执行。
// ExampleNetworkPlugin/ExampleNetworkService 为示例工程中的业务类型。
let networkService = ExampleNetworkService()
try MWB.registerPlugin(name: "network") {
    ExampleNetworkPlugin(service: networkService)
}
```

业务类的入口形状如下；请求校验和服务实现使用上述示例文件，不把网络同步阻塞放在这里：

```swift
final class ExampleNetworkPlugin: MWBPlugin {
    // service 由工厂注入并保存；完整初始化及实现见 Example/NetworkPlugin.swift。
    @objc(mwb_request:context:responder:)
    func request(_ params: Any?, context: MWBPluginCallContext,
                 responder: MWBPluginResponder) {
        // 校验 params，调用宿主异步服务。
        // 完成时：responder.success(["status": 200, "headers": [:], "body": "..."])
        // 失败时：responder.failure(1001, message: "Network request failed")
        // 有取消句柄时：context.onCancel(cancel)
        // 发送事件：context.emit("requestFinished", data: ["url": url, "status": status])
    }

    override func dispose() {
        // 释放当前文档持有的观察器等资源；不要释放宿主共享服务。
    }
}
```

这是入口形状示意，不能只复制空方法作为业务实现。**精确签名必须是 `Any? / MWBPluginCallContext / MWBPluginResponder -> Void`**，selector 必须是 `mwb_方法名:context:responder:`。基类自动查找并缓存受标记的方法，普通辅助方法不暴露。Core 可校验 selector、参数数量、对象 ABI、Void 返回及冲突，但 ObjC 编码无法区分对象的具体 Swift 类；不要把 params 改成 String 或把 context 改成其他对象。Swift cast trap/fatalError 也不是可恢复业务异常。

`context` 提供只读 `containerId/documentId/pageURL`、弱引用 `controller`、`emit` 和 `onCancel`。`responder` 可从任意线程完成，重复响应被忽略；`success()` 省略 result，`success(NSNull())` 保留显式 null。入口和 dispose 在主线程，耗时工作由宿主异步服务执行。

## 3. Android：继承、注解、注册

引入 `mwb` library 并安装宿主配置，见 [Android README](../MWB-Android/README.md)。Sample 已包含 `NetworkPlugin`、`NetworkService` 和 `HostNetworkService`：

```kotlin
import com.mobilewebbridge.MWB
import com.mobilewebbridge.plugins.MWBMethod
import com.mobilewebbridge.plugins.MWBPlugin
import com.mobilewebbridge.plugins.MWBPluginCallContext
import com.mobilewebbridge.plugins.MWBPluginResponder

// 放在 Application.onCreate 中，在首个容器创建之前注册。
MWB.registerPlugin(name = "network") { NetworkPlugin(appNetworkService) }

class NetworkPlugin(private val service: NetworkService) : MWBPlugin() {
    @MWBMethod
    fun request(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        // 完整校验、异步请求与结果封装见 Sample 的 NetworkPlugin.kt。
        // 业务入口不写 when，也不使用 @JavascriptInterface。
    }

    override fun dispose() {
        // 释放当前文档的业务资源；宿主共享服务由宿主管理。
    }
}
```

方法必须是公开实例方法，参数精确为 `Any? / MWBPluginCallContext / MWBPluginResponder`，返回 Unit；不使用 suspend 或返回 Future 改变桥签名。签名错误/重载冲突返回 `-1105`，未知或未标记方法返回 `-1101`。AAR 的 consumer rules 保留运行时注解、方法名称/签名和反射基类边界；Sample release 开启 R8 用于验证。

传入对象为 JSONObject；结果可用 JSONObject/JSONArray、字符串键 Map/List 及 JSON 基础值。`success()` 省略结果，`success(null)` 保留 null。`context.activity` 在当前可信文档有效时提供可空 Activity；不要保存为全局强引用。后台服务通过 responder 完成，通过 `context.onCancel(cancel)` 登记取消，通过 `context.emit("requestFinished", data)` 发当前插件事件。

## 4. H5：声明类型并组合

```ts
import { createMWB, defineNativePlugin, MWBBridgeError,
         type GenericAsyncResult } from "mobile-web-bridge";

interface NetworkMethods {
  // 声明与两个原生实现相同的参数和结果，不声明运行时方法表。
  request(params: { url: string; method: "GET" | "POST"; headers?: Record<string, string>; body?: string }):
    Promise<GenericAsyncResult<{ status: number; headers: Record<string, string>; body: string }>>;
}
type NetworkEvents = { requestFinished: { url: string; status: number } };

const network = defineNativePlugin<NetworkMethods, NetworkEvents>()({
  name: "network", timeoutMs: 30000
});
const mwb = createMWB({ plugins: [network] });

// 查询原生是否安装插件；不会创建插件实例或自动请求网络。
if (await mwb.hasPlugin("network")) {
  const off = mwb.network.on("requestFinished", event => console.log(event));
  try {
    const response = await mwb.network.request({ url: "https://example.com", method: "GET" });
    console.log(response.result?.status, response.result?.body);
  } catch (error) {
    if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
  } finally {
    off(); // 组件卸载时也应清理长时间订阅。
  }
}
```

`createMWB({plugins: [...]})` 默认附带完整 basic。未组合描述时 JS 没有 network 命名空间；组合了描述但 App 没注册时为 `-1100`。`hasPlugin` 只查插件存在，不保证新方法已实现；首版没有 hasMethod，调用缺失方法会以 `-1101` 拒绝。Proxy 属性存在不能用于能力检测。

默认 npm ESM 导出和 `mwb.iife.js` 仅预组装 basic。普通 HTML 使用自定义插件时，编译自己的入口：

```ts
// my-mwb.ts：复用上面的类型、描述和组合代码，然后挂到全局。
window.mwb = mwb;
```

```bash
# 在接入方项目中安装 esbuild 后，构建可供普通 HTML 加载的入口。
pnpm exec esbuild my-mwb.ts --bundle --format=iife --platform=browser --outfile=public/my-mwb.js
```

HTML 在业务脚本之前加载 `my-mwb.js`，不要再加载另一个默认脚本覆盖 window.mwb。Vue 直接 ESM 导入并导出本地组合实例即可。可运行范例为 `MWB-Demo-Web/src/plugins-sdk.ts`，构建会自动生成 `plugins.iife.js`。

## 5. 注册、生命周期及名称

- 只在创建首容器前注册，之后冻结；非法名、重名或覆盖 Core/basic 会报配置错误。
- 工厂按活动文档惰性调用，应快速返回。子容器继承工厂快照，但插件实例独立；共享连接池、登录态通过工厂注入宿主服务。
- 整页导航/销毁撤销 pending、调用取消和 dispose；暂时隐藏、前后台或 SPA/hash 路由保留实例。旧结果和事件不会进入新文档。
- 默认超时 30000ms，可配置整数 1..120000ms，包含工厂初始化。JS 也有兜底计时；晚到结果忽略。首版无用户主动取消 API。
- 名称使用 `[a-z][a-zA-Z0-9_]*`。插件名保护当前 49 个根方法、basic/version/hasPlugin、pluginSession/pluginInfo/invokePlugin/pluginEvent、dispatchEvent/backBtnPressed。插件/方法/事件还避开 `on/then/catch/finally/toJSON/inspect/constructor/prototype/__proto__`。
- `.on()` 返回解绑函数，不启动原生业务、不重放事件。`context.emit` 仅发往本插件的当前文档，不能指定其他容器。

两端仅加载自己控制的可信页面。iOS 新网关拒绝 iframe；Android 的 DSBridge JavascriptInterface 暴露给所有 frame，不能嵌入不可信 frame。documentId 用于文档生命周期隔离，不能防同页恶意脚本或 XSS。生产插件还需执行宿主自己的账号、业务权限和参数校验。

## 6. 调试和发布

在 `MWB-Demo-Web` 执行 `pnpm run sync:native`，重新构建两个 App，首页点击“自定义原生插件”。同一页面也可部署到 HTTPS 静态站点；加载线上页面前另配置容器 allowedOrigins。容器来源与业务网络目标域名是独立策略。

Sample 网络仅允许 HTTPS example.com/httpbin.org、默认 443、GET/POST、文本 body/响应不超过 1 MiB，禁止 GET body 和 URL 认证信息。iOS 跟随重定向时重新检查目标；Android 不自动跟随，返回 3xx。示例没有自动请求外网，不把网络客户端加入 basic。

新增支付等插件时，流程相同：两端实现并标记 `pay`、分别注册 `payment` 工厂，H5 声明 PaymentMethods 并组合 payment 描述，然后重新发布含原生实现的 App。仅增加 npm 包或更新 H5 不能安装原生代码；插件包仍可使用 npm/Pod/Maven 自身版本，注册处无需版本字段。

内部协议为 1。缺旧壳网关/协议不兼容 `-1106`；缺插件 `-1100`；缺方法 `-1101`；非法参数/JSON `-1102`；超时 `-1103`；文档失效 `-1104`；配置/执行异常 `-1105`；不可信 `-1006`。业务错误建议用正整数。旧页已销毁时，不承诺旧 JS 还能观察到拒绝，但不会向新文档投递。

JS 预览版 `0.1.1-beta.1` 已发布 npm；Android `0.1.1` 已发布 Maven Central；当前 JS/iOS/Android 配套版本为 `0.1.4`，npm 与 Maven Central 制品已公开并通过公共仓库独立消费验证，iOS Tag 源码的独立 Pod 接入验证通过，未发布公共 CocoaPods Specs。当前验证覆盖 JS/H5 集成、Android Robolectric 与 R8 产物、iOS macOS 原生检查和 generic iOS 编译，并新增框架外的独立消费检查。真机 WebView/外网/前后台仍需按本版本验收；版本组合及支持边界见 [版本说明](versioning.md)。

## 内置首屏通知

当前源码的 `mwb.basic.notifyPageReady()` 复用文档网关的内置分发，不是宿主注册的业务插件，也不需要 defineNativePlugin。其余 basic 方法继续使用既有入口。Android Maven `0.1.1` 已包含原生端支持；本轮配套版本为 JS/iOS/Android `0.1.4`，此前 `0.1.3` 亦已支持，已发布的 JS `0.1.1-beta.1` 和旧原生 `0.1.0` 不包含此能力；详见 [加载状态与首屏就绪](page-lifecycle.md)。
