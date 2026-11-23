# 原生导航栏外观

以下扩展从 `0.1.6` 起提供，请配套使用 JS、iOS 和 Android SDK。`0.1.5` 不包含新增外观字段、宿主默认外观和打开时的外观参数。分发状态见[版本说明](versioning.md)。

## 打开时配置，首帧生效

`navigateTo`、`redirectTo` 和 `setNavigationBarTheme` 共享以下可选外观字段。打开/替换时直接用于目标容器创建，无需等待目标 H5 ready 后补设。

```ts
// 实际调用按页面目的选择打开或替换。
const options = {
  url: targetUrl, title: '页面标题', hidden: false,
  color: '#F6FBFA', titleColor: '#0B4148', buttonColor: '#049F91',
  backButtonStyle: 'arrowText' as const, backButtonText: '返回', showBackButton: true,
  separatorVisible: true, separatorColor: '#DFE8E5',
  titleFontSize: 17, titleFontWeight: 'semibold' as const, buttonFontSize: 16
};
await mwb.navigateTo(options);
// 替换当前容器也可直接传入相同外观字段。
void mwb.redirectTo(options).catch(console.error);
```

`hidden` 默认仍为 `true`，传入颜色/字体不会自动显示导航栏。Android 必须省略 `waitForReady`；iOS 可使用该参数，离屏准备不改变来源导航栏，准备失败/取消保留来源状态。打开/替换的栈行为见[导航说明](navigation.md)。

| 字段 | 取值 | 作用 |
| --- | --- | --- |
| color | 6 位十六进制，可带 # | 不透明背景色 |
| titleColor | 同上 | 标题色；未显式配置按钮色时仍同时影响按钮 |
| buttonColor | 同上 | 返回箭头/文字、关闭及右侧操作的独立颜色 |
| buttonBackgroundVisible | boolean（仅 iOS） | `false` 去掉返回和右侧操作的系统玻璃底，`true` 恢复；iOS 26 起生效，Android 请省略 |
| backButtonStyle | text / arrow / arrowText | 原生文字、箭头、箭头加文字 |
| backButtonText | 非空白 string | 返回文案，默认“返回”，箭头模式仍使用此可访问名称 |
| showBackButton | boolean | 返回控件显隐，不改变系统返回或真实页面栈 |
| separatorVisible | boolean | 底部细分隔线显隐 |
| separatorColor | 6 位十六进制，可带 # | 线条颜色，不自动改变显隐 |
| titleFontSize | 有限 number，0 < size <= 32 | 标题基准字号，iOS pt / Android sp |
| titleFontWeight | regular / medium / semibold / bold | 系统标题字体字重 |
| buttonFontSize | 有限 number，0 < size <= 28 | 原生文字按钮基准字号 |

缺省字段保留当前值，undefined 不传原生。新增字段的 null、错误类型、非法色值/枚举/字号返回 `-1001`，整次不应用；打开/替换会在创建目标前拒绝无效外观。不支持的其他打开参数仍为 `-1004`。iOS 无导航控制器且未指定 isPopUp=true 时，带外观的 navigateTo 返回 `-1004`。

在 iOS 26 及更新版本中，可用 `await mwb.setNavigationBarTheme({ buttonBackgroundVisible: false })` 隐藏当前页两个按钮的背景。`navigateTo` 和 `redirectTo` 传相同字段可在目标首帧隐藏背景。省略时遵循默认外观或保留当前页已有设置，按钮颜色、点击热区和回调保持原有行为。深色栏可搭配较亮的 `buttonColor`，例如 `#74E1D5`。

## 合并与兼容

初始外观逐字段采用：**打开参数 > 宿主默认主题 > 平台/导航宿主基线**。之后目标文档的 setNavigationBarTheme 可局部覆盖；目标在 iOS 离屏准备期间的更新也保留到首次显示。宿主 configureContainer 之后再应用明确的打开外观字段。旧 title/hidden 时序不变：Android 宿主无条件 hidden=true 仍会覆盖原有 hidden 参数。

只使用旧主题字段时保留旧配色行为。在宿主未配置 buttonColor 的新容器中，可用下面的旧调用让标题和按钮继续联动：

```js
await mwb.setNavigationBarTheme({ titleColor: '#112233' });
await mwb.setNavigationBarTheme({ titleColor: '#445566' }); // 按钮也随标题色更新
```

Demo 的“复制标题颜色到按钮”会设置显式相同颜色；继续修改标题色时，按钮保持该显式值。宿主、打开参数或当前页一旦显式配置 buttonColor，后续仅更新 titleColor 不再覆盖按钮色；同一调用同时给两色时 buttonColor 优先。宿主已有 buttonColor，打开参数只给 titleColor，会保留宿主按钮色。

iOS 在默认主题为空且全程没有使用新能力时保留旧共享栏继承行为。该导航栈成功使用非空默认外观、新主题字段或任意打开外观字段后，启用外观隔离：以后新建/替换容器从宿主基线计算，不继承父页局部覆盖；已有页面保留自己的状态，返回时恢复。失败/取消不启用隔离，两个 UINavigationController 不共享基线。Android 各 Activity 本身独立。未配置返回样式时 iOS 仍为文字、Android 仍为箭头。

## 宿主默认外观

MWBConfiguration 的可选 navigationBarAppearance 被新容器继承，不包含 title、hidden、showBackButton 或文档操作；页面角色仍由调用方决定。

```swift
// UIColor 也可以来自宿主已有的颜色资源。
let appearance = MWBNavigationBarAppearance(
    color: .systemBackground, titleColor: .label, buttonColor: .systemTeal,
    backButtonStyle: .arrowText, backButtonText: "返回", separatorVisible: true,
    titleFontSize: 17, titleFontWeight: .semibold, buttonFontSize: 16,
    buttonBackgroundVisible: false)
let configuration = MWBConfiguration(initialURL: url, navigationBarAppearance: appearance)
let page = MWBWebViewController(configuration: configuration)
```

```kotlin
// 值配置随 Intent 传入目标 Activity。
val appearance = MWBNavigationBarAppearance(
    color = Color.WHITE, titleColor = Color.BLACK, buttonColor = Color.rgb(4, 159, 145),
    backButtonStyle = MWBBackButtonStyle.ARROW_TEXT, separatorVisible = true,
    titleFontSize = 17f, titleFontWeight = MWBTitleFontWeight.SEMIBOLD, buttonFontSize = 16f)
val configuration = MWBConfiguration(initialUrl = url, navigationBarAppearance = appearance)
startActivity(MWBActivity.createIntent(this, configuration))
```

## 操作、返回及文字缩放

打开方法不接收来源页的 actionTxt/actionExt/onActionClick，由目标文档自行调用 setNavigationBarTheme 注册。回调留在当前 JS 实例，不跨文档传函数。

```ts
// 局部外观更新保留已有 handler，显式新函数替换，空操作文字清除。
await mwb.setNavigationBarTheme({ actionTxt: '保存', actionExt: 'draft', onActionClick: handleSave });
await mwb.setNavigationBarTheme({ titleColor: '#0B4148', hidden: false });
await mwb.setNavigationBarTheme({ actionTxt: '' });
```

同一 JS 实例的主题请求按调用顺序执行；失败保留旧 handler，不阻断下一次请求。整页导航/重载/失败清除旧文档操作资格；hash 路由保留。push 不清除前页仍存活文档的操作，pop 恢复该页自己的主题、显隐和按钮。

返回点击继续走既有 H5 返回链；iOS 侧滑保留且直接执行系统返回。在 `0.2.1` 中，从有栏页侧滑回无栏页时，不透明栏随页面移出，半透明栏随手势淡出。从无栏页侧滑回有栏页时，目标页的栏随页面露出，正文顶部保持稳定；取消手势会恢复当前页。showBackButton=false 只隐藏控件。iOS 根页无可 pop 层级时不制造返回按钮；Android 保留已有根页和网页历史返回语义。关闭按钮、状态栏明暗仍仅 Android 支持；图片按钮尚不支持。

iOS 保留标准 UINavigationBar 高度，显式字号经系统缩放后标题上限 32pt、按钮 28pt，长标题单行截断；Android 使用 sp 并允许栏为大字体增高。触控区域至少 iOS 44pt / Android 48dp；箭头采用系统语义方向。未配置字体字段时保持旧字体策略。
