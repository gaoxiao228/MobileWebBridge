# Mobile Web Bridge JavaScript SDK

MWB 为 iOS 和 Android 的 Web 容器提供统一 JS API。原生通信由 DSBridge 3.x 完成。

当前版本为 `0.1.3`，与同一 Git Tag 下的 iOS/Android 源码配套。下方安装命令固定为 `0.1.3`；分发状态见 [版本说明](https://github.com/gaoxiao228/MobileWebBridge/blob/main/docs/versioning.md)，需要本地构建时可按 [源码构建与安装](https://github.com/gaoxiao228/MobileWebBridge#从源码构建-js-sdk) 使用。

正式仓库：[gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。建议固定精确版本；Git Tag 与 npm 分发标签独立，原生接入与支持范围见 [项目 README](https://github.com/gaoxiao228/MobileWebBridge#readme)。

## 安装和使用

```bash
# 固定项目版本；原生端也使用配套版本。
npm install mobile-web-bridge@0.1.3
```

```ts
import { mwb } from "mobile-web-bridge";

const info = mwb.getAppInfoSync();
await mwb.toast({ msg: `App: ${info.appId}` });
// basic 命名空间与根兼容入口共享函数；同步方法仍同步返回。
const sameInfo = mwb.basic.getAppInfoSync();
```

右上角文字按钮由当前 Web 页面设置，点击回调仍在当前页面执行：

```ts
await mwb.setNavigationBarTheme({
  actionTxt: "保存",
  actionExt: "draft-42",
  onActionClick: ({ actionExt }) => console.log("保存按钮被点击", actionExt)
});
```

再次设置会替换原回调；传入 `actionTxt: ""` 可移除按钮。`onActionClick` 不会序列化传给原生，原生点击时只回传 `actionExt`。目前 iOS、Android 均支持文字按钮，`actionIcon` 尚不支持。

网页也可直接引入发布包中的 `dist/mwb.iife.js`，通过 `window.mwb` 调用。应在 MWB 原生容器内加载；普通浏览器中的原生调用会给出“桥未就绪”错误。

完整的 H5 方法示例由 [`MWB-Demo-Web`](https://github.com/gaoxiao228/MobileWebBridge/tree/main/MWB-Demo-Web) 维护，可构建为静态站点并同步到 iOS、Android 示例 App。SDK 面向浏览器，不提供 SSR/Node 服务端或 CommonJS 入口；Nuxt 等环境只在客户端导入。

## 首屏就绪通知

当前源码新增 `await mwb.basic.notifyPageReady()`（也可用根入口 `mwb.notifyPageReady()`），用于 H5 主动通知当前原生容器首屏准备完成。无需注册业务插件，重复调用幂等。成功表示原生接受通知，不代表宿主已完成展示。

此能力请配套使用 JS、iOS 和 Android `0.1.3`。此方法走文档身份网关，等待上限 30000ms；旧原生和普通浏览器明确失败。调用时机、原生回调和重载规则见 [接入说明](https://github.com/gaoxiao228/MobileWebBridge/blob/main/docs/page-lifecycle.md)。

## 同步与异步调用

调用方式由 SDK 的方法声明和对应原生实现共同决定。`mwb.basic.xxx()` 与 `mwb.xxx()` 是同一实现；TypeScript 返回非 Promise 的方法直接使用，返回 Promise 的方法使用 `await` 或 `.then/.catch`。

### basic 同步方法

basic 中有 9 个同步原生入口：

- 信息读取：`getAppInfoSync`、`getDeviceInfoSync`、`getClipboardDataSync`、`getNetworkTypeSync`。
- 本地存储：`setStorageSync`、`getStorageSync`、`removeStorageSync`、`clearStorageSync`。
- 调试设置：`setEnableDebug`，立即返回 `void`，名称没有 `Sync` 后缀。

同步调用直接返回业务值或 `void`，不会返回 `{errCode, result}` 包装；失败会抛错。桥必须已在当前 MWB 容器中可用（相关错误为 `-1000`），`getAppInfoSync` 还要求宿主配置应用信息；同步不代表无需权限或平台支持。

```ts
import { mwb, MWBBridgeError } from "mobile-web-bridge";

// 同步读取少量本地数据；不存在的键返回 undefined。
try {
  mwb.basic.setStorageSync("theme", "dark", "settings");
  const theme = mwb.basic.getStorageSync<string>("theme", "settings");
  console.log(theme);
} catch (error) {
  if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
  else console.error(error);
}
```

同步调用仍有跨桥、序列化和系统访问成本；避免在循环、滚动或动画回调中反复调用，也不要在同步原生路径中等待异步任务。`await mwb.getAppInfoSync()` 会先执行同步工作再等待其返回值，不会解除同步阻塞。

### basic 异步方法

既有 21 个 basic 异步原生入口（例如 `toast`、`navigateTo`、`chooseImage`、`scanCode`）返回 `Promise<GenericAsyncResult<T>>`。成功为 `{errCode: 0, result?: T}`；失败拒绝 Promise，不应只在 `.then` 中检查 errCode。

```ts
import { mwb, MWBBridgeError } from "mobile-web-bridge";

// 在页面按钮等业务入口中调用；await 保证后续代码在本次响应之后执行。
async function copyMessage() {
  try {
    await mwb.basic.setClipboardData({ data: "Hello MWB" });
    await mwb.basic.toast({ msg: "已复制" });
  } catch (error) {
    if (error instanceof MWBBridgeError) console.error(error.errCode, error.errorMsg);
    else console.error(error);
  }
}
```

Promise 完成仅表示该方法约定的操作完成：`navigateTo` 成功不等于新页面首屏完成，`toast` 成功不等于提示已消失。具体结果仍以各方法契约为准。

除新增 `notifyPageReady()` 外，既有 basic 异步调用没有统一超时及文档失效兜底；原生未回调时可能持续等待。业务添加等待超时只会停止自己的等待，不代表原生操作已取消；支付等操作尤其不能据超时推断业务失败或直接重试。

### 事件与自定义插件

18 个 JS 句柄/事件方法不属于上述 30 个原生入口。`onAppShow`、`registerHandler` 等注册方法立即返回，回调后续触发；`await mwb.onAppShow(handler)` 不会等待应用进入前台。使用对应 `off` / `unRegister` 方法解绑；插件 `.on()` 返回解绑函数。

通过 `defineNativePlugin` 声明的业务方法**只支持 `Promise<GenericAsyncResult<T>>`**。即便原生立即调用 `responder.success`，JS 仍应使用异步契约；不能声明普通对象返回值，也没有 `sync: true` 配置。`hasPlugin` 同样返回 Promise。

自定义插件默认超时 30000ms，可配置 `timeoutMs` 为 1..120000 的整数；超时、文档失效和迟到结果按插件 Core 规则处理，这项保证不能套用到其他 basic 方法。取消能否终止实际业务取决于宿主服务；支付等不可撤销的操作还需独立查询最终状态。完整 Swift/Kotlin/H5 实现和同步读取替代方案见 [插件调用方式与线程约定](https://github.com/gaoxiao228/MobileWebBridge/blob/main/docs/native-plugins.md#调用方式与线程约定)。

## 插件组合与构建

当前源码默认提供 basic 的 49 个方法；已发布包为原有 48 个。源码分为 `container`、`device`、`media`、`storage` 四组；事件和 JS 句柄始终包含在 SDK 内。`basicPlugin` 为完整组合，`--plugins=basic` 可构建全量 basic；与旧分组混用时去重。原有 `createMWB(legacyPlugins)` 数组裁剪入口保留，只在 basic 下映射选中的方法。重复方法或覆盖 Core/事件入口的配置直接报错。

```bash
pnpm install
pnpm build
pnpm build:composition --plugins=container,device
npm pack --dry-run
```

组合脚本在 `dist` 输出 `mwb.container-device.iife.js`。组合产物只暴露选中的功能方法，适合按应用需求自行部署；npm 默认入口仍提供全量接口。`npm pack` 会通过 prepack 自动重新构建并检查入口、声明和许可，防止空包或旧产物。构建和打包命令不执行公开发布。

## 自定义原生插件

原生 App 必须先安装对应 Swift/Kotlin 插件；JS 描述不会生成原生业务代码。`createMWB({plugins: [...]})` 默认包含完整 basic，并增加插件命名空间：

```ts
import { createMWB, defineNativePlugin, type GenericAsyncResult } from "mobile-web-bridge";

interface NetworkMethods {
  // 实际请求由宿主原生网络服务执行。
  request(params: { url: string; method: "GET" | "POST"; headers?: Record<string, string>; body?: string }):
    Promise<GenericAsyncResult<{ status: number; headers: Record<string, string>; body: string }>>;
}
type NetworkEvents = { requestFinished: { url: string; status: number } };

const network = defineNativePlugin<NetworkMethods, NetworkEvents>()({
  name: "network", timeoutMs: 30000
});
const sdk = createMWB({ plugins: [network] });
if (await sdk.hasPlugin("network")) {
  const off = sdk.network.on("requestFinished", event => console.log(event));
  const response = await sdk.network.request({ url: "https://example.com", method: "GET" });
  console.log(response.result); // 保留统一 envelope，不自动解包。
  off(); // 组件卸载时也应解绑。
}
```

没有 `version` 或运行时 `methods` 数组。两阶段 builder 保留插件名字面量及方法/事件类型。新插件只支持异步 Promise；`hasPlugin` 查询原生注册且不创建实例，不代表所有方法都存在；首版不提供 hasMethod。默认 ESM/IIFE 仍只含 basic，使用业务插件时应构建自己的入口脚本。完整 Swift/Kotlin 接入、生命周期及浏览器构建见 [接入文档](https://github.com/gaoxiao228/MobileWebBridge/blob/main/docs/native-plugins.md)；可运行入口见 Demo 的 `src/plugins-sdk.ts`。

调用参数、成功结果和事件只接受 JSON：拒绝循环、函数、undefined 字段、非有限数字、非普通对象或 getter/setter。省略参数按 null 处理；显式结果 null 保留。超时默认 30000ms，允许整数 1..120000ms，超时以 `MWBBridgeError(-1103)` 拒绝。缺插件/方法分别为 `-1100/-1101`，旧壳无网关为 `-1106`，完整错误表见接入文档。

名称采用 `[a-z][a-zA-Z0-9_]*`。插件名不得占用当前 49 个根方法、basic/version/hasPlugin、pluginSession/pluginInfo/invokePlugin/pluginEvent、dispatchEvent/backBtnPressed 或以下探测名。业务方法和事件禁止 `on/then/catch/finally/toJSON/inspect/constructor/prototype/__proto__`；`on` 专用于订阅。读取方法属性不发请求，Proxy 的 Promise/JSON/Symbol 探测不会调用原生。不要通过 `typeof sdk.network.someMethod` 判断原生是否支持该方法，原生才会根据标记方法返回 `-1101`。

## 接口约定

- 异步方法返回 `{ errCode, errorMsg?, result? }`；`errCode === 0` 表示成功，非零错误通过 Promise 拒绝并保留错误码。
- 同步方法直接返回附件声明的数据；桥未就绪或方法不可用时抛出 `MWBBridgeError`。
- `clearStorageSync(groupName?)` 清空指定分组，参数已根据旧实现修正。
- iOS 的 `exitApp()` 默认返回不支持；Android 默认只关闭当前 MWB 容器。
- 应用信息、角标、推送和原生页面能力需要宿主应用配置；未配置会返回明确错误。

完整参数、返回类型和方法列表见本包 TypeScript 声明。浏览器可通过 `mwb.onPageShow(handler)` 等方法订阅事件，用对应 `off` 方法解绑。宿主使用 `mwb.dispatchEvent`、`mwb.backBtnPressed` 及 `mwb.<handlerName>` 调用 JS。

## 来源

MWB 的通信底层基于 [DSBridge](https://github.com/wendux/DSBridge-Android)（MIT）。接口能力参考当前工作区的旧项目，MWB 不依赖 Cordova。

包内包含 LICENSE 和 THIRD_PARTY_NOTICES.md，ESM/IIFE/组合脚本保留完整许可注释；单独分发 bundle 时也不要移除这些注释。
