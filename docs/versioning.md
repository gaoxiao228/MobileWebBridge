# 版本、支持范围与升级

正式仓库：[gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。npm 包：[mobile-web-bridge](https://www.npmjs.com/package/mobile-web-bridge)。npm 与 Maven Central 状态核实日期为 2026-11-06；本轮 `0.1.3` 已公开，并分别通过公共 registry / Maven 仓库的独立消费检查。

## 当前状态

| 组件 | 当前版本 | 获取方式与状态 |
| --- | --- | --- |
| JS SDK | `0.1.3` | 已发布 npm，latest 指向本版本 |
| iOS | `0.1.3` | 共享源码 Tag / 本地 Pod；未发布公共 CocoaPods Specs |
| Android | `0.1.3` | 已发布 Maven Central；公共坐标独立消费通过 |
| Demo Web | `0.1.3` | 与本轮 SDK 配套，不是独立发布的 SDK；页面可静态部署 |

`0.1.3` 包含默认与自定义 HTML 错误页、业务首页回调，以及默认 `allowedOrigins` 星号配置。本轮 JS 与 Android 制品均已公开；iOS 通过共享 Tag 或本地 Pod 接入，不提供公共 CocoaPods Specs 安装。Git Tag、npm 与 Maven 是分别核验的分发渠道。

本次核实 npm 的 `latest` 指向 `0.1.3`，`next` 保留 `0.1.1-beta.1`；稳定版接入请固定 `0.1.3`，不要使用旧的预览标签。核实实时状态可运行：

```bash
npm view mobile-web-bridge dist-tags versions --json --registry=https://registry.npmjs.org/
```

仓库中的文档与包链接元数据可以先于下一次 npm 发布更新；已经发布的同名同版本不可覆盖，当前仓库新增信息不会自动出现在旧 npm 包中。

## 已验证的组合

| H5 SDK | iOS / Android 源码 | 插件协议 | 范围 |
| --- | --- | --- | --- |
| `0.1.3` 源码 | iOS / Android `0.1.3` 源码 | `1` | basic、原生插件、首屏通知、默认与自定义错误页、业务首页回调 |

该表描述源码和自动化检查覆盖的组合，不是对所有设备/WebView 的兼容认证。本轮源码以正式仓库的共享 Tag `0.1.3` 为准；宿主仍需按目标设备验证实际业务。

## 多端共享 Git Tag

每轮仓库发布只创建一个不带平台前缀的 Git Tag，例如 `0.1.1`，共同标识 iOS、Android、JS 和 Demo 所在的同一个源码提交。各端不再单独创建平台 Tag；构建和发布本轮制品时使用该 Tag 对应的源码。

| 共享 Git Tag | iOS Pod 版本 | Android Maven 版本 | JS npm 版本 | 状态 |
| --- | --- | --- | --- | --- |
| `0.1.3` | `0.1.3` | `0.1.3` | `0.1.3` | GitHub Tag、npm 与 Maven Central 已公开；iOS Git Pod 验证通过 |
| `0.1.1` | `0.1.0` | `0.1.1` | `0.1.1-beta.1` | Android Maven 已发布，含加载与就绪回调；H5 仍需当前 JS 源码，iOS 未发布公共 Specs |

共享 Tag 是仓库源码标识，各端已发布版本不得覆盖。本轮将源码版本统一为 `0.1.3`，Podspec 的 `s.source[:tag]` 对应共享 Tag `0.1.3`，支持 Git Pod 或本地源码接入。历史 Tag `0.1.2` 已移除，npm `0.1.2` 包继续保留；既有共享 Tag `0.1.1` 保留。Maven 坐标中的版本和 npm 包版本按本表记录，不由 Git Tag 自动修改。

npm 的 `latest`、`next` 是包分发标签，与 Git Tag 分开管理，不需要因此再创建 JS 专属的 Git Tag。

JS 与原生版本独立，不要求三个版本号相同。`mwb.version` 只代表当前 JS 包，不代表 App 内的原生版本。注册插件无需传入版本号；协议由 Core 管理。

## 环境边界

- 开发本仓库：Node.js 22.12+、pnpm 10；JS 发布命令在依赖安装后使用 npm，不要求额外全局 pnpm。
- iOS：iOS 15+、Swift 5.9+、CocoaPods、完整 Xcode；本次本机已验证 Xcode 27，CI 使用 runner 已安装的 Xcode，并打印其版本。
- Android：minSdk 24、compileSdk 35、JDK 17；当前构建组合为 AGP 8.9.2、Kotlin 2.0.21、Gradle 8.11.1。设备需使用可用的系统 WebView；尚未给出所有旧 WebView 版本的验证矩阵。
- H5：浏览器端 ESM 或 IIFE，页面运行于 MWB 原生容器。普通浏览器可预览 UI，原生调用会报告桥未就绪。
- 不提供 Node 服务端/SSR 入口；Nuxt 等项目应只在客户端导入和调用，避免服务端顶层加载 SDK。当前不提供 CommonJS 入口。

Android 扫码依赖 Google Play 服务，相机选择返回缩略图；iOS 不支持通过 `exitApp()` 退出进程。完整差异见 [兼容表](compatibility.md)，不要把方法存在等同于当前设备支持。

## 升级约定

1. Beta 阶段固定精确版本，升级前阅读 CHANGELOG；有破坏性变化时明确写出迁移步骤。
2. 预览版使用 `next`/`beta`，正式稳定版才使用 `latest`；发布命令禁止将带预发布标识的版本发到 `latest`。首次标签行为仍以 npm 实际结果为准，发布后必须查询核对。
3. 升级 JS 不会安装原生插件。App 没有该插件时为 `-1100`，没有新方法为 `-1101`，旧壳无插件网关为 `-1106`；业务应提供降级行为。
4. 保持 `mwb.xxx()` 与 `mwb.basic.xxx()` 兼容；新增 App 业务通过插件扩展，不覆盖 basic/Core。
5. 升级前在独立宿主与目标设备上验证安装、桥接调用、权限和生命周期行为，确认所用版本组合适用于业务场景。
