# 页面打开与替换

`navigateTo` 打开新容器并保留当前页；`redirectTo` 用新容器替换当前页：

```text
当前：           P → A
navigateTo(B)： P → A → B
redirectTo(B)： P → B
```

`redirectTo` 是当前源码新增能力，已发布的 `0.1.4` 制品不包含此方法。请配套更新 JS 与两端原生源码；单独更新 H5 不能让旧 App 获得原生入口。

## 调用方式

```js
// 两端立即替换 A；目标 B 中负责后续业务初始化。
mwb.basic.redirectTo({
  url: 'https://example.com/b',
  title: '页面 B',
  hidden: true
}).catch(error => {
  // 只有 A 仍存在时才在这里展示参数、启动或准备失败。
  console.error(error.errCode, error.message);
});
```

`mwb.redirectTo` 与 `mwb.basic.redirectTo` 使用同一个方法，返回类型为 `Promise<GenericAsyncResult<undefined>>`。A 成功被替换后会销毁，不要依赖 A 的成功回调或 `await` 后的代码继续执行业务；由 B 自己初始化、展示结果。成功仅表示替换已发起，不表示 B 已完成业务数据请求。

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `url` | `string` | 必填 | 沿用宿主可信来源与本地资源限制 |
| `title` | `string` | 不设置 | 新容器标题 |
| `hidden` | `boolean` | `true` | 是否隐藏新容器导航栏 |
| `waitForReady` | `boolean` | iOS 为 `false` | 仅 iOS 支持；Android 必须省略，包括 `false` 也不能传 |

其他字段（包括 `isPopUp`）返回 `-1004`。参数使用明确类型，不将数字、字符串或 `null` 自动转换为布尔值。

## 页面与返回行为

- 只替换当前页，前面的页面实例和顺序保留；B 调用 `navigateBack()` 后关闭 B，返回 P，不会恢复 A。
- A 是根页时，B 成为新根页；之后 `navigateBackToRoot()` 的目标是 B。没有上一页时，沿用各端根容器的返回/关闭规则，不额外创建 P。
- B 使用独立 WebView，不复制 A 的网页历史、滚动位置、JS 内存、按钮回调、事件订阅或插件实例。容器配置与插件定义沿用宿主配置；Cookie、存储仍遵循已有共享规则。
- 默认直接替换，不使用向前 push 的滑入动画。B 的标题和导航栏按新容器规则初始化。
- 系统返回拦截及 B 后续产生的 H5 历史仍按既有规则处理；被移除的 A 不会成为其中的历史项。

## iOS：可选等待准备

```js
// 仅 iOS：B 主文档加载和绘制准备完成后再替换。
mwb.redirectTo({ url: 'https://example.com/b', waitForReady: true })
  .catch(error => console.error(error.errCode, error.message));
```

默认立即替换，随后加载失败由 B 的错误页展示。启用等待时，SDK 自动执行主文档加载与 WebKit 绘制准备，无需 H5 报告 ready；整个准备过程最多 3000ms，加载/绘制失败或超时返回 `-1002`，不提交替换。准备完成不代表异步业务数据已就绪。

来源页离开、App/所属 Scene 失活时取消准备并返回 `-1005`；若来源文档已失效，旧回复会被丢弃。同一来源页已有准备任务时，另一次 `navigateTo` 或 `redirectTo` 返回 `-1004`，不并行创建目标页。

第一版要求来源是空闲 `UINavigationController` 的当前栈顶，包括根页面和弹窗内导航控制器的栈顶。没有导航控制器的独立容器、非栈顶、被其他页面遮挡或正在转场时返回 `-1004`，不会退化成打开新页面或更换宿主窗口。

## Android：立即替换

Android 启动 B 后结束 A；启动请求失败时返回 `-1002` 并保留 A。暂不支持等待网页加载，必须省略 `waitForReady`；显式传入该字段返回 `-1004`。启动成功后的网页加载失败由 B 展示错误页，不回退到已移除的 A。

来源 Activity 必须处于恢复状态，且没有已发起、尚未返回的 `navigateTo`；隐藏来源的迟到替换请求返回 `-1004`。从子页返回来源后可以重新替换。已提交替换的旧 Activity 不再接受新的 `navigateTo`/`redirectTo` 请求，避免快速重复调用创建多个目标页。

## 常见错误

| 错误码 | 相关场景 |
| --- | --- |
| `-1001` | 参数缺失、类型错误、目标 URL 无效或不受信任 |
| `-1002` | iOS 准备失败/超时，Android 启动失败 |
| `-1003` | App 未包含新原生方法 |
| `-1004` | 不支持的字段、iOS 容器/转场状态不允许替换、重复导航 |
| `-1005` | 准备取消或来源文档已失效 |
| `-1006` | 发起调用的页面不可信 |

两端 Demo 的“替换当前页面”方法默认替换到主 H5 页面 `index.html`，方法详情中可编辑目标地址；iOS 额外提供等待绘制与立即转场的对照按钮。
