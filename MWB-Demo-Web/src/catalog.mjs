// 每个公开方法在这里有且仅有一个示例；args 是页面初始展示的 JSON 参数数组。
const item = (name, title, description, group, args = [], extra = {}) =>
  ({ name, title, description, group, args, ...extra });

export const groups = [
  { id: 'container', label: '容器与导航' },
  { id: 'device', label: '设备与系统' },
  { id: 'storage', label: '本地存储' },
  { id: 'media', label: '图片与文件' },
  { id: 'events', label: '事件与句柄' }
];

export const catalog = [
  item('setEnableDebug', '切换调试模式', '设置原生容器的调试开关。', 'container', [true], { note: 'Android 仅在可调试构建中生效。' }),
  item('toast', '显示原生提示', '在当前 App 中显示一条短消息。', 'container', [{ msg: '你好，Mobile Web Bridge' }]),
  // 开新页面由目录方法或详情运行按钮明确触发，无需重复弹出网页确认框。
  item('navigateTo', '打开容器页面', '在新的 MWB 页面打开当前示例地址，默认不显示导航栏。', 'container', [{ url: '{{currentURL}}', title: 'MWB 示例子页' }]),
  item('navigateBack', '返回上一页', '结束当前 MWB 页面，可传回调数据。', 'container', [{ from: 'demo' }], { confirm: '将关闭当前页面。' }),
  item('navigateBackToRoot', '返回根页面', '回到 MWB 容器的首页。', 'container', [], { confirm: '将返回容器首页。' }),
  item('openExternalBrowser', '使用系统浏览器打开', '把 HTTPS 地址交给系统浏览器。', 'container', [{ url: 'https://example.com' }], { confirm: '将离开当前 App 打开系统浏览器。' }),
  item('setNavigationBarTheme', '设置导航栏主题', '打开独立容器页面配置并预览导航栏。', 'container', [{ title: 'MWB 示例', color: 'ffffff', titleColor: '172033' }], { note: '点击方法行打开可视化配置页；此处仍可编辑 JSON 调试原始方法。' }),
  item('cleanWebviewCache', '清理网页缓存', '清除容器使用的 WebView 缓存。', 'container', [], { confirm: '将清理 WebView 缓存。' }),
  item('exitApp', '关闭容器', '请求关闭当前应用容器。', 'container', [], { note: 'iOS 返回不支持；Android 默认关闭当前 MWB Activity。', confirm: '将关闭当前容器；iOS 会返回不支持。' }),
  item('openNativePage', '打开宿主原生页面', '按宿主注册的名称打开原生页面。', 'container', [{ pageName: '{{nativePageName}}' }], { note: 'iOS 示例名称为 demo，Android 示例名称为 sample；其他宿主需自行注册。', confirm: '将离开 H5 页面，打开宿主原生页面。' }),

  item('openAppAuthorizeSetting', '打开应用授权设置', '跳转系统中的当前 App 设置页。', 'device', [], { confirm: '将离开当前页面打开系统设置。' }),
  item('getAppInfoSync', '读取应用信息', '同步读取宿主提供的 App ID、版本和环境。', 'device', [], { note: '需要宿主实现 appInfo。' }),
  item('setBadgeCount', '设置应用角标', '设置应用图标上的数字角标。', 'device', [{ count: 3 }], { note: '需要宿主配置角标能力。' }),
  item('getDeviceInfoSync', '读取设备信息', '同步读取系统、机型和安全区域信息。', 'device'),
  item('getClipboardDataSync', '读取剪贴板', '同步读取系统剪贴板内容。', 'device', [], { note: '读取可能触发系统隐私提示。' }),
  item('setClipboardData', '写入剪贴板', '将指定文本写入系统剪贴板。', 'device', [{ data: 'MWB 示例文本' }]),
  item('makePhoneCall', '打开拨号', '把电话号码交给系统拨号器。', 'device', [{ phoneNumber: '{{phoneNumber}}' }], { confirm: '将打开系统拨号器。' }),
  item('getNetworkTypeSync', '读取网络类型', '同步获取当前网络连接类型。', 'device'),
  item('getNotificationSwitchStatus', '读取通知开关', '查询当前 App 的系统通知授权状态。', 'device'),

  item('setStorageSync', '写入分组存储', '把对象保存到 demo 分组中的 demo-key。', 'storage', ['demo-key', { message: 'Hello MWB' }, 'demo']),
  item('getStorageSync', '读取分组存储', '读取 demo 分组中的 demo-key。', 'storage', ['demo-key', 'demo']),
  item('removeStorageSync', '移除存储项', '删除 demo 分组中的 demo-key。', 'storage', ['demo-key', 'demo'], { confirm: '将删除 demo-key 的存储值。' }),
  item('clearStorageSync', '清空分组存储', '清除 demo 分组中的全部存储值。', 'storage', ['demo'], { confirm: '将清空 demo 分组。' }),

  item('compressImage', '压缩图片', '把所选图片的 Base64 压缩到目标大小。', 'media', [{ base64Image: '{{imageBase64}}', maxLength: 512000 }]),
  item('scanCode', '扫描二维码', '打开原生扫码界面并返回内容。', 'media', [{ scanType: ['qrCode'], hideAlbum: true }], { note: 'Android 需要 Google Play 服务；不支持相册扫码。' }),
  item('saveImageToPhotosAlbum', '保存图片到相册', '将所选图片保存到系统相册。', 'media', [{ base64Image: '{{imageBase64}}' }], { confirm: '将向系统相册写入图片。' }),
  item('chooseImage', '选择图片', '从系统相册选择一张图片。', 'media', [{ sourceType: 'album', sizeType: ['original'], count: 1 }], { note: '返回的是原生文件路径，可供后续路径类方法使用。' }),
  item('openFile', '打开 PDF', '用原生能力打开 PDF 文件。', 'media', [{ url: '{{pdfURL}}', fileName: 'demo.pdf' }], { note: 'Android 只接受 HTTPS PDF 或 MWB 缓存路径。', confirm: '将打开原生 PDF 查看页面。' }),
  item('checkRequestCameraPermissions', '检查相机权限', '检查并按需请求相机权限。', 'media', [{}]),
  item('convertImagePathToBase64', '图片路径转 Base64', '读取前一步获得的原生图片路径。', 'media', [{ path: '{{imagePath}}' }], { note: 'Android 只读取 MWB 缓存目录内的路径。' }),

  item('registerHandler', '注册 JS 句柄', '让宿主原生代码通过 nativeGreeting 调用 H5。', 'events', ['nativeGreeting'], { note: '先注册句柄，再由宿主调用容器方法：iOS 为 callJSHandler，Android 为 callJsHandler。' }),
  item('unRegisterHandlers', '解绑全部同名句柄', '移除指定名称下所有 JS 回调。', 'events', ['nativeGreeting']),
  item('unRegisterHandler', '解绑单个 JS 回调', '使用注册时保存的函数引用解绑。', 'events', ['nativeGreeting']),
  item('checkHandlerExist', '检查 JS 句柄', '查询指定名称是否已有 JS 回调。', 'events', ['nativeGreeting']),
  item('onNetworkStatusChange', '监听网络变化', '订阅原生发送的网络类型变化事件。', 'events'),
  item('offNetworkStatusChange', '取消网络监听', '取消当前页面注册的网络变化回调。', 'events'),
  item('onAppShow', '监听 App 前台', '订阅 App 回到前台事件。', 'events'),
  item('offAppShow', '取消 App 前台监听', '取消当前页面注册的前台回调。', 'events'),
  item('onAppHide', '监听 App 后台', '订阅 App 进入后台事件。', 'events'),
  item('offAppHide', '取消 App 后台监听', '取消当前页面注册的后台回调。', 'events'),
  item('onRemoteNotificationReceive', '监听推送消息', '订阅宿主主动发送的推送事件。', 'events', [], { note: '宿主需要主动调用 sendEvent 才会收到消息。' }),
  item('offRemoteNotificationReceive', '取消推送监听', '取消当前页面注册的推送回调。', 'events'),
  item('onPageShow', '监听页面显示', '订阅容器页面显示事件。', 'events'),
  item('offPageShow', '取消页面显示监听', '取消当前页面注册的显示回调。', 'events'),
  item('onPageHide', '监听页面隐藏', '订阅容器页面隐藏事件。', 'events'),
  item('offPageHide', '取消页面隐藏监听', '取消当前页面注册的隐藏回调。', 'events'),
  item('onBackBtnPressed', '处理物理返回键', '注册返回键回调，本示例返回 false 让原生继续返回。', 'events', [], { note: 'Android 物理返回键会触发；iOS 导航返回也会询问该句柄。' }),
  item('offBackBtnPressed', '取消返回键处理', '移除当前页面的返回键回调。', 'events')
];
