# MWB 0.1 接口兼容表

当前源码的 iOS/Android 容器均新增默认本地 HTML 错误页、自定义模板、重试、`onGoHome` 与宿主 `configureContainer`；旧 Pod `0.1.0` 和 Maven `0.1.1` 不包含这些能力。错误页属于原生容器能力，不增加业务 JS 方法，详见 [错误页接入](error-pages.md)。

此表以 JS、iOS 和 Android 的 `0.1.4` 源码及插件协议 1 为基准；npm/Maven 制品已公开，并通过公共仓库独立消费验证，历史版本和环境边界见 [版本说明](versioning.md)。`0` 为成功；`-1001` 参数错误、`-1002` 操作失败、`-1003` 方法缺失、`-1004` 平台不支持、`-1005` 宿主能力未配置、`-1006` 页面不可信、`-1007` 用户取消、`-1008` 权限拒绝或操作忙。异步方法返回 `{errCode, result?, errorMsg?}`；失败的 JS Promise 会拒绝。

| 方法 | iOS | Android | 备注 |
| --- | --- | --- | --- |
| `setEnableDebug` | 原生 | 原生 | Android 仅调试构建可开启 |
| `navigateTo` | 原生 | 原生 | 只允许可信 URL；两端默认隐藏新容器导航栏，可传 `hidden: false` 显示；iOS 另支持 `isPopUp`、`waitForReady`（默认 false，SDK 自动完成主文档加载及绘制准备后转场，最多 3000ms）；Android 应省略 `waitForReady`；其他选项返回 `-1004` |
| `redirectTo` | 原生（未发布） | 原生（未发布） | 将 `P → A` 替换为 `P → B`，默认隐藏导航栏；iOS 要求空闲导航栈顶，支持可选 `waitForReady`，最多准备 3000ms；Android 必须省略该字段；详见[页面打开与替换](navigation.md) |
| `navigateBack` | 原生 | 原生 | 结束当前 MWB 页面 |
| `navigateBackToRoot` | 原生 | 原生 | 返回 MWB 容器根页 |
| `setNavigationBarTheme` | 原生 | 原生 | 两端支持标题、颜色、显示/隐藏及右上角文字按钮 `actionTxt`；`onActionClick` 留在 JS，点击回传 `actionExt`。Android 另支持返回/关闭按钮及状态栏明暗。`actionIcon` 等未实现字段返回 `-1004` |
| `openExternalBrowser` | 原生 | 原生 | HTTP(S) 地址 |
| `cleanWebviewCache` | 原生 | 原生 | Android 保留宿主全局 Cookie |
| `openAppAuthorizeSetting` | 原生 | 原生 | 打开应用设置 |
| `toast` | 原生 | 原生 | 短时提示 |
| `getAppInfoSync` | 宿主 | 宿主 | 必须实现 `appInfo` |
| `setBadgeCount` | 宿主 | 宿主 | 未配置返回 `-1005` |
| `getDeviceInfoSync` | 原生 | 原生 | `deviceId` 可由宿主提供 |
| `getClipboardDataSync` | 原生 | 原生 | 系统剪贴板限制仍适用 |
| `setClipboardData` | 原生 | 原生 | 写剪贴板 |
| `makePhoneCall` | 原生 | 原生 | Android 打开拨号器 |
| `getNetworkTypeSync` | 原生 | 原生 | Android 无法判定蜂窝代际时返回 `unknown` |
| `getNotificationSwitchStatus` | 原生 | 原生 | 查询通知状态 |
| `exitApp` | 不支持 | 原生 | iOS 返回 `-1004`；Android 默认仅关闭容器 |
| `openNativePage` | 宿主 | 宿主 | 只使用宿主显式注册的页面 |
| `compressImage` | 原生 | 原生 | Base64 输入输出 |
| `scanCode` | 原生 | 原生 | Android 依赖 Google Play Code Scanner；不支持相册扫码，显式 `hideAlbum:false` 返回 `-1004` |
| `saveImageToPhotosAlbum` | 原生 | 原生 | 权限拒绝返回错误 |
| `chooseImage` | 原生 | 原生 | Android `all` 弹出来源选择，`count` 最多 20；相机路径为缓存缩略图 |
| `openFile` | 原生 | 原生 | Android 仅允许 HTTPS PDF 或 MWB 缓存路径 |
| `checkRequestCameraPermissions` | 原生 | 原生 | 返回 `{grant: boolean}` |
| `convertImagePathToBase64` | 原生 | 原生 | Android 仅读取 MWB 缓存目录 |
| `setStorageSync` | 原生 | 原生 | 同步分组存储 |
| `getStorageSync` | 原生 | 原生 | 同步分组读取 |
| `removeStorageSync` | 原生 | 原生 | 同步分组删除 |
| `clearStorageSync` | 原生 | 原生 | 签名为 `clearStorageSync(groupName?)` |
| `registerHandler` | JS | JS | 注册供原生调用的句柄 |
| `unRegisterHandlers` | JS | JS | 解绑指定句柄的全部回调 |
| `unRegisterHandler` | JS | JS | 解绑单个回调 |
| `checkHandlerExist` | JS | JS | 查询 JS 句柄 |
| `onNetworkStatusChange` | JS + 原生事件 | JS + 原生事件 | 监听网络变化 |
| `offNetworkStatusChange` | JS | JS | 解绑网络监听 |
| `onAppShow` | JS + 原生事件 | JS + 原生事件 | 应用前台事件 |
| `offAppShow` | JS | JS | 解绑前台事件 |
| `onAppHide` | JS + 原生事件 | JS + 原生事件 | 应用后台事件 |
| `offAppHide` | JS | JS | 解绑后台事件 |
| `onRemoteNotificationReceive` | JS + 宿主事件 | JS + 宿主事件 | 宿主主动调用 `sendEvent` |
| `offRemoteNotificationReceive` | JS | JS | 解绑推送监听 |
| `onPageShow` | JS + 原生事件 | JS + 原生事件 | 页面显示事件 |
| `offPageShow` | JS | JS | 解绑页面监听 |
| `onPageHide` | JS + 原生事件 | JS + 原生事件 | 页面隐藏事件 |
| `offPageHide` | JS | JS | 解绑页面监听 |
| `onBackBtnPressed` | JS + 原生事件 | JS + 原生事件 | Android 系统返回键优先询问 H5 |
| `offBackBtnPressed` | JS | JS | 解绑返回键处理 |

上表 48 方法归为 basic，`mwb.basic.xxx` 和 `mwb.xxx` 是相同函数，继续走原同步/异步通道。`mwb.version` 为 SDK 元数据，不属于 basic 方法。默认入口未预装任何业务插件。

## 自定义原生插件 Core

| 能力 | iOS | Android | 约定 |
| --- | --- | --- | --- |
| `MWB.registerPlugin(name, factory)` | 抛错 Swift 注册 | Kotlin 注册 | 首容器前，仅名称/工厂，首容器后冻结 |
| `MWBPlugin` 自动分发 | 固定 `@objc(mwb_方法:context:responder:)` | `@MWBMethod` | 接入方无 handle 或 methods 清单；必须遵守精确签名 |
| `mwb.hasPlugin(name)` | 支持 | 支持 | 查询原生注册，不创建实例，不保证具体方法；无 hasMethod |
| `mwb.<plugin>.<method>(params)` | 支持 | 支持 | Promise envelope，仅 JSON；默认 30s，1..120000ms |
| `mwb.<plugin>.on(name, handler)` | 支持 | 支持 | 返回解绑函数，按插件/文档隔离，无历史重放 |
| 页面生命周期 | 按活动主文档 | 按活动主文档 | 导航/销毁取消并 dispose；SPA/暂时隐藏保留；子容器独立实例 |

内部协议 1 使用同步 pluginSession、异步 pluginInfo/invokePlugin 与 pluginEvent，既有 basic 方法不经过业务插件网关；新增 notifyPageReady 复用该网关的内置分发。插件名不能覆盖 basic/Core/根成员，标记方法之外的辅助方法不会暴露。Swift 的 ObjC 编码只能验证对象 ABI，不能识别对象的具体 Swift 类；作者必须精确使用 `Any? / MWBPluginCallContext / MWBPluginResponder -> Void`。Android consumer rules 保留注解、精确方法和基类以供 R8 后反射。

| 错误码 | 含义 |
| --- | --- |
| `-1006` | 页面不可信 |
| `-1100` | 插件未注册 |
| `-1101` | 业务方法未标记或不支持 |
| `-1102` | 参数、JSON、名称或调用结构不合法 |
| `-1103` | 超时（包含工厂创建） |
| `-1104` | 文档/容器失效 |
| `-1105` | 工厂、签名配置或执行异常 |
| `-1106` | 协议不兼容或旧壳无插件网关 |

业务错误建议用正整数，HTTP 状态属于 network 插件数据，不等同于桥错误。旧 App 仍可使用 basic，但不能通过安装新 npm 包获得尚未编译到 App 的原生插件。完整用法见 [接入文档](native-plugins.md)。

生产环境只应将自己控制的网页来源加入白名单。Android DSBridge 3.0.0 的 `JavascriptInterface` 会进入页面内所有 frame，宿主页面不得嵌入不可信 frame；插件 documentId 用于生命周期隔离，不能作为 frame 隔离或防 XSS 的安全凭证。iOS 新网关基于 WKFrameInfo 拒绝 iframe。iOS 相机、相册和 Android 硬件能力仍需在目标设备上验收。本次插件测试和编译未替代真机 WebView、真实外网及前后台验收。

## 加载状态与首屏就绪

本能力已随配套的 `0.1.3` 提供，并由本轮 `0.1.4` 继续支持。当前 basic 源码共 50 个方法；新增的 `notifyPageReady()` 复用文档身份网关，其他既有 basic 原生方法仍使用各自入口。

| 能力 | iOS | Android |
| --- | --- | --- |
| 容器 `onLoadStateChange` / `onPageReady` / `isPageReady` | 支持 | 支持 |
| 子类 `pageDidBecomeReady()` | 支持 | 不提供，使用容器闭包 |
| `mwb.basic.notifyPageReady()` / 根别名 | 文档网关，30000ms 有界等待 | 文档网关，30000ms 有界等待 |

首次注册时机、导航边界、平台加载回调限制及错误语义见 [接入说明](page-lifecycle.md)。

## iOS 自动预热与导航绘制准备（0.1.4）

`MWBConfiguration.webViewPrewarmingEnabled` 默认 true，只预热空白引擎，不执行目标业务页面。`navigateTo.waitForReady` 为可选布尔值，默认 false；true 时 SDK 自动等待目标主文档加载与绘制准备，3000 ms 内未成功则返回 `-1002` 并保留源页。源页离开或后台取消为 `-1005`，源文档失效时丢弃旧回复，同源准备中再次导航为 `-1004`。成功表示已发起原系统转场，不表示动画结束或异步业务数据完成。Android 不支持这两个选项；H5 在 Android 应省略 `waitForReady`。旧 iOS 收到该参数返回不支持，需同步更新原生 SDK。
