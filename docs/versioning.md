# 版本、支持范围与升级

正式仓库：[gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)。npm 包：[mobile-web-bridge](https://www.npmjs.com/package/mobile-web-bridge)。npm 状态核实日期为 2026-11-03；Android Portal 状态由维护者于 2026-11-04 确认。

## 当前状态

| 组件 | 当前版本 | 获取方式与状态 |
| --- | --- | --- |
| JS SDK | `0.1.1-beta.1` | 已发布 npm；建议显式安装该版本或 `@next` |
| iOS | `0.1.0` | 源码/本地 Pod；根 Podspec 已适配单仓库，尚未发布 CocoaPods Specs |
| Android | `0.1.0` | Central Portal 已为 PUBLISHED；公共仓库独立消费验证待完成，也支持源码和本机 Maven |
| Demo Web | `0.1.0` | 联调示例，不是独立发布的 SDK；页面可静态部署 |

本次核实 npm 的 `latest` 与 `next` 都指向 `0.1.1-beta.1`，**尚无稳定版**。直接安装默认标签也会得到 Beta，不能据此推断其已稳定。核实实时状态可运行：

```bash
npm view mobile-web-bridge dist-tags versions --json --registry=https://registry.npmjs.org/
```

仓库中的文档与包链接元数据可以先于下一次 npm 发布更新；已经发布的同名同版本不可覆盖，当前仓库新增信息不会自动出现在旧 npm 包中。

## 已验证的组合

| H5 SDK | iOS / Android 源码 | 插件协议 | 范围 |
| --- | --- | --- | --- |
| `0.1.1-beta.1` | 当前 `0.1.0` 原生实现 | `1` | basic、根兼容入口、自定义异步原生插件 |

该表描述源码和自动化检查覆盖的组合，不是对所有设备/WebView 的兼容认证。正式对外提供时，应在此补充真实提交 SHA、共享 Tag、仓库地址和设备验收记录。

## 多端共享 Git Tag

每轮仓库发布只创建一个不带平台前缀的 Git Tag，例如 `0.1.1`，共同标识 iOS、Android、JS 和 Demo 所在的同一个源码提交。各端不再单独创建平台 Tag；构建和发布本轮制品时使用该 Tag 对应的源码。

| 共享 Git Tag | iOS Pod 版本 | Android Maven 版本 | JS npm 版本 | 状态 |
| --- | --- | --- | --- | --- |
| `0.1.1` | `0.1.0` | `0.1.0` | `0.1.1-beta.1` | 重建后的共享源码 Tag，含加载与就绪回调；包版本不变，已有 npm/Maven 制品不包含该新增能力，iOS 未发布公共 Specs |

共享 Tag 是仓库源码标识，各端包版本仍独立管理，已发布版本不得覆盖。重建仓库后移除旧 Tag，当前仅保留 `0.1.1`；Podspec 的 `s.source[:tag]` 显式引用该源码 Tag，Pod 版本仍为 `0.1.0`，本次不发布 CocoaPods Specs。Maven 坐标中的版本和 npm 包版本按本表记录，不由 Git Tag 自动修改。历史 `0.1.0` Git 接入应改用源码 Tag `0.1.1`。

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
