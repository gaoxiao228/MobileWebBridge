# 更新记录

## 0.1.5 — 2026-11-09

- JS、iOS、Android 新增 `redirectTo`：将 `P → A` 替换为 `P → B`，新容器默认隐藏导航栏，支持替换根页面；原 `navigateTo` 保留新增页面行为。
- iOS `redirectTo` 支持可选 `waitForReady`，最多准备 3000ms，失败保留来源页；第一版要求来源位于空闲导航栈顶。Android 立即替换，必须省略 `waitForReady`。
- 两端共享 Demo 新增 `redirectTo` 方法行，默认替换到主 H5 页面；同步接口类型、插件命名保护和接入说明。

- JS、iOS、Android 与 Demo 版本统一为 `0.1.5`，Demo 构建号递增为 5；npm 与 Maven Central 制品已公开，公共仓库独立消费验证通过；iOS Tag 源码的独立 Pod Release 接入验证通过。

## 0.1.4 — 2026-11-07

- iOS 默认自动预热一个空白备用 WebView，稳定显示且加载完成后补充；支持通过 `MWBConfiguration.webViewPrewarmingEnabled` 关闭，后台和内存警告时释放备用实例。
- iOS `navigateTo` 新增可选 `waitForReady: true`：SDK 自动完成目标主文档加载与绘制准备后再发起原系统转场，无需 H5 报告 ready；默认仍立即转场。
- 等待总时限为 3000 ms，失败或超时保留源页；隔离文档替换和迟到快照，支持源页离开/后台取消、重复请求拦截及准备期间视口变化。
- 同步 JS 类型、两端内置网页和版本 0.1.4，Demo 构建号统一为 4；iOS 提供等待/立即转场对照，Android 保持原导航行为并省略 iOS 专有参数。
- 自动绘制准备不保证异步业务数据、懒加载内容或系统弹层后续布局完成。npm 与 Maven Central 制品已公开，并通过公共仓库独立消费验证；iOS Tag 源码的独立 Pod 接入验证通过。

## 0.1.3 — 2026-11-06

- JS、iOS、Android 与 Demo 版本统一为 `0.1.3`，同步 README 安装命令、Git Pod Tag、Maven 坐标和双端示例资源。
- 延续默认与自定义 HTML 错误页、GET 重试、业务首页回调和默认星号来源配置，接口行为与上一轮源码保持一致。
- 两端 Demo 构建号统一递增为 3；npm 与 Maven Central 制品已公开，并通过独立消费检查。
- 源码改用共享 Tag `0.1.3`；旧 `0.1.2` Git Tag 已移除，已经发布的 npm `0.1.2` 保留。

## 0.1.2 — 2026-11-06（历史源码版本）

- JS、iOS、Android 与 Demo 源码版本统一为 `0.1.2`，npm `0.1.2` 已发布；对应 Git Tag 已移除，后续源码接入使用 `0.1.3`。
- 两端主文档加载失败时展示内置“轻盈纸页”HTML，支持 GET 重试、自定义本地 HTML/CSS/JS 和模板失败后的原生兜底。
- 新增容器 `onGoHome` 与宿主 `configureContainer`，由业务定义首页动作；未配置时隐藏首页按钮。
- `allowedOrigins` 默认使用 `"*"`，允许全部 HTTP/HTTPS 来源加载及使用原生桥；显式来源列表和空集合仍可收紧范围，本地文件与其他协议限制保持不变。
- 修复 iOS 缺失本地资源经过符号链接时误判不可信，以及 CSP 注入改变 HTML 文档模式的问题；隔离 Android 失败引擎迟到回调。
- 同步两端自定义模板资源与接入文档，Demo 首页不展示专用错误页入口。

## 随 0.1.2 提供的其他源码改进

- 新增每个容器独立的加载状态/首屏就绪回调与只读状态，H5 通过 `notifyPageReady()` 主动报告当前文档就绪；整页导航重置、重复报告幂等，沿用文档身份校验。
- iOS 开放容器继承和 `pageDidBecomeReady()` 重写入口，校验与去重由内部固定执行；补充双端失败终态处理与外部接入示例。以上能力随本轮源码提供。

- 补齐真实仓库、npm 项目链接、当前发布状态与三端版本兼容说明。npm 元数据随下一次包版本发布生效，不覆盖既有包。
- 根 Podspec 适配单仓库，同时保留 iOS Example 的子目录本地接入。
- Android 保留本地 Maven 发布与独立消费检查，增加 Dokka API 文档包和显式启用的 Central Portal/PGP 签名配置；尚未上传公共 Maven 仓库。
- iOS 作者设为 gaoxiao228，各端共用不带平台前缀的仓库发布 Tag；补充 SDK 隐私清单、资源 Bundle 及最终宿主打包检查。
- 统一本项目版权署名、补充 npm 作者，并将已发布 Beta 版本号纳入源码；第三方声明保持原文。
- 增加独立 JS/iOS/Android 消费验证、CI 配置和真机验收清单；CI 在推送后才会实际运行。

## JS 0.1.1-beta.1 — 2026-11-03

- 已发布到 [npm](https://www.npmjs.com/package/mobile-web-bridge/v/0.1.1-beta.1)，仍为预览版，无稳定版承诺。
- 提供 basic 及根兼容入口、自定义原生插件描述/组合、类型声明和 ESM/IIFE 产物。
- 发布流程支持指定版本、预演及检查；构建测试已移除对全局 pnpm 的隐式依赖。

## 0.1.0 — 未发布，预览阶段

- 提供 Swift iOS Web 容器、Kotlin Android Web 容器及统一 JS SDK。
- basic 包含 48 个公开方法，保留根兼容入口；支持按需组合浏览器脚本。
- 支持宿主自定义原生插件、类型化 JS 调用、事件、超时和文档清理。
- 提供共用 Vue 移动端 Demo、导航栏配置、原生 network 插件示例及加载耗时展示。
- 完善 MIT/第三方声明、npm 自动构建打包和干净源码导出。

此节为初始源码基线。后续 JS 发布状态见上方；原生仍以源码/本地制品接入。自动化检查与构建不代表已完成全部目标设备验收。
