# MWB Demo Web

这是 Mobile Web Bridge 的 Vue 3 移动端方法示例工程。`src/` 是页面的唯一应用源码，构建产物可部署到任意支持 HTTPS 的静态站点，也可打包进 iOS、Android 示例 App。页面提供 SDK 的 48 个方法示例。

## 构建

前提：安装 Node.js、pnpm，并已在 `../MWB-JS` 执行 `pnpm install`。

```bash
cd MWB-Demo-Web
pnpm install
npm test
npm run build
```

`npm run build` 会先构建 `MWB-JS`，再由 Vite 把 Vue 页面和运行时打成普通脚本 `demo.js`，与 CSS、`mwb.iife.js` 一起放入 `dist/`。插件页另构建 `plugins.iife.js`，包含 basic 和 network 的 JS 描述。将整个 `dist/` 目录部署到静态站点即可发布测试页面；无需后端。普通浏览器可查看代码和参数，调用原生方法时会提示需要在 MWB 容器中打开。

移动端页面使用“方法目录 → 方法详情”两级视图，方便在 WebView 中单手查找和运行示例。桌面宽度会显示双栏，内容与移动端相同。开发时运行 `npm run dev`，访问 `http://127.0.0.1:18743/`；本地开发服务不连接原生桥。

首页与导航样式子页都声明不可缩放的 viewport，并在触屏设备上禁用正文长按选词菜单；表单输入仍允许选择文字。原生 MWB 容器还会在 WebView 层处理手势和菜单。

页面顶部显示本次整页加载的两个耗时：**白屏时间**从原生容器首次可见到 Vue 首屏完成绘制；**MWB 可调用**从同一起点到 `getDeviceInfoSync()` 首次成功返回。SDK 脚本加载后立即尝试原生调用，避免把 Vue 启动时间算进桥的可用时间。重新打开或整页导航会重新统计，切换方法详情不会重置。普通浏览器没有原生容器起点，显示占位提示。数字用于定位当前设备和本次加载的问题，冷启动与热启动应分别观察。

## 接入 iOS 与 Android 示例

```bash
npm run sync:native
```

同步命令将同一组文件复制到：

- `../MWB-iOS/Example/Resources/`：Xcode 将资源打进 App Bundle。示例 `AppDelegate` 从 Bundle 读取 `index.html`，交给 `MWBWebViewController` 加载。
- `../MWB-Android/sample/src/main/assets/`：Gradle 将资源打进 APK。示例 `SampleWebActivity` 启动后直接用 `file:///android_asset/index.html` 加载本地页面。

两个示例默认使用本地 HTML，基础能力演示离线可运行，network 示例仍需网络。修改 `src/` 或 `MWB-JS` 后重新执行 `npm run sync:native`，再重新构建原生 Demo。页面中的相对路径 `./mwb.iife.js` 在静态站点、iOS Bundle 和 Android Assets 中一致。同步同时包含 LICENSE.txt、THIRD_PARTY_NOTICES.txt；Vue 和 DSBridge bundle 也保留完整许可注释，静态部署时一起保留。

Demo 页面在原生容器中打开时会自动调用 `mwb.setEnableDebug(true)`，iOS 上可直接从 Mac Safari 的“开发”菜单检查当前 WebView；新打开的示例子页也会自行开启。

`navigateTo` 新页面默认不显示导航栏；传 `hidden: false` 可以显示。点击“设置导航栏主题”方法行会打开独立的 `navigation-theme.html`，初始仍隐藏导航栏；取消“隐藏导航栏”并应用后可预览标题、颜色和右上角文字按钮。填写按钮文字与点击回传数据后应用样式，点击原生按钮即可在页面上看到 `onActionClick` 的结果；清空按钮文字并再次应用可移除按钮。Android 子页另有返回按钮、关闭按钮和状态栏选项；右侧信息按钮仍进入原始 JSON 调试详情。

配置页底部的“打开新容器页面”会再次通过 `mwb.navigateTo` 打开同一配置页，方便观察子页导航栏及返回上一页后的样式。每次打开的页面都有独立 WebView，默认隐藏原生导航栏。配置页保留网页返回按钮；普通 Demo 子页通过 URL 中的 `mwbChild=1` 显示顶部返回箭头，调用 `mwb.navigateBack()`。这些网页入口同时适用于本地 HTML 和已加入白名单的线上页面。

如需让原生 App 加载线上测试页，宿主还必须把该 HTTPS 来源加入 `allowedOrigins`；默认示例没有放开任何远程来源。只有自己控制的网页才应加入白名单。

## 试用顺序

首页“自定义原生插件”进入 `native-plugins.html`。该 Vue 子页会检查 App 是否注册 network，提供 GET/POST、headers/body 输入、结果及事件记录、订阅/解绑和打开同页新容器。默认开启原生调试，不会在启动或能力查询时自动请求外网。普通浏览器只显示未连接原生，不能把浏览器 fetch 当作原生插件测试成功。

两个 Demo 均在 App 启动时注册 network，其业务请求由各自宿主网络层执行。示例只允许 HTTPS 的 `example.com` 和 `httpbin.org`（默认 443、无 URL 用户信息），GET 不接受 body，请求 body/UTF-8 文本响应上限 1 MiB。iOS 跟随重定向前重新检查策略；Android 关闭自动重定向并返回 3xx 响应。HTTP 非 2xx 仍返回 `{status,headers,body}`；传输失败使用业务码 1001。实际接入请替换为自己的网络客户端和域名策略。H5 页面可信来源白名单与原生网络目标域名白名单是两套配置。

`src/plugins-sdk.ts` 是自定义浏览器入口范例，只有 TypeScript 方法和事件类型、插件名和超时，不含版本及运行时方法表。更换原生插件需要重新编译 App；修改 JS 描述/页面后执行同步并重新构建 Demo。完整三端步骤见 [自定义原生插件接入](../docs/native-plugins.md)。

先运行 `getAppInfoSync`、`toast`、`setStorageSync` 等低风险方法。图片相关方法可先选择本地图片，或先执行 `chooseImage` 再执行 `convertImagePathToBase64`。事件示例需要先订阅；`nativeGreeting` 句柄可由集成方的原生代码主动调用。宿主能力未配置或平台不支持时，页面会显示原生错误码。
