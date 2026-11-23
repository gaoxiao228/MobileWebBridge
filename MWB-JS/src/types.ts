// MWB 的公开契约以用户提供的旧 JS SDK 类型为基准，版本和产品命名已更新。
export const version = "0.2.1";

type TYPE_VERSION = typeof version;

export type GenericAsyncResult<T = any> = {
	errCode: number;
	errorMsg?: string;
	result?: T;
};

export type ScanType = "qrCode" | "barCode";
export type NetworkStatus = "wifi" | "2g" | "3g" | "4g" | "5g" | "ethernet" | "none" | "unknown";


export type ParamToast = {
	msg: string;
};

export type ClipboardData = {
	data: string;
};

export type ParamBadgeCount = {
	count: number;
};
export type ParamStorage = {
	groupName?: string;
	key: string;
	data: any;
};
export type ParamRemoveStorage = {
	groupName?: string;
	key: string;
};

export type ReturnStorageResult = {
	data: any;
};
export type ParamStorageClear = {
	groupName?: string;
};


/** 三个导航方法共享的可选原生外观；打开时在目标容器首帧前应用。 */
export type NavigationBarAppearanceOptions = {
	/** 6 位十六进制背景色，可带 #。 */
	color?: string;
	/** 未显式设置 buttonColor 时，沿用标题和按钮同色的旧行为。 */
	titleColor?: string;
	/** 显式指定后，后续 titleColor 更新不再影响按钮。 */
	buttonColor?: string;
	/** 仅 iOS（26 起生效）：false 隐藏系统按钮背景，true 恢复系统样式；Android 请省略。 */
	buttonBackgroundVisible?: boolean;
	backButtonStyle?: "text" | "arrow" | "arrowText";
	/** 默认“返回”；不能是空白字符串。 */
	backButtonText?: string;
	showBackButton?: boolean;
	separatorVisible?: boolean;
	separatorColor?: string;
	/** 系统缩放前字号，0 < size <= 32；iOS 缩放后上限 32pt。 */
	titleFontSize?: number;
	titleFontWeight?: "regular" | "medium" | "semibold" | "bold";
	/** 系统缩放前字号，0 < size <= 28；iOS 缩放后上限 28pt。 */
	buttonFontSize?: number;
};

/** 替换当前原生容器；Android 必须省略 waitForReady，不支持创建新弹窗。 */
export type ParamRedirectTo = NavigationBarAppearanceOptions & {
	/** 目标地址，沿用容器的可信来源限制。 */
	url: string;
	/** 新容器标题。 */
	title?: string;
	/** 是否隐藏导航栏，默认 true。 */
	hidden?: boolean;
	/** 仅 iOS：等待主文档加载和绘制准备，默认 false；最多 3000ms，失败保留当前页。 */
	waitForReady?: boolean;
};

export type ParamNavigateTo = NavigationBarAppearanceOptions & {
	url: string;
	/** 默认 true；样式参数不会自动显示导航栏。 */
	hidden?: boolean;
	title?: string;
	/** 仅 iOS，默认 false；Android 必须省略。 */
	waitForReady?: boolean;
	/** 仅 iOS：打开新的原生导航弹窗。 */
	isPopUp?: boolean;
	/** @deprecated 打开方法不支持；由 Android 目标文档通过主题方法设置。 */
	isBright?: boolean;
	/** @deprecated 打开方法不支持；由 Android 目标文档通过主题方法设置。 */
	showCloseButton?: boolean;
	/** @deprecated 操作与回调由目标文档注册，不能从来源页传入。 */
	actionTxt?: string;
	/** @deprecated 原生尚不支持图片按钮。 */
	actionIcon?: string;
	/** @deprecated 操作载荷由目标文档设置。 */
	actionExt?: string;
	/** @deprecated 原生不支持沉浸状态栏参数。 */
	translucentStatusBars?: boolean;
	/** @deprecated 原生不支持此回调参数；使用已有返回事件。 */
	callbackFunction?: GenericCallbackFunc | string;
};

export type ParamExternalBrowse = {
	url: string;
};

export type ParamNavigationBarTheme = NavigationBarAppearanceOptions & {
	hidden?: boolean;
	title?: string;
	/** 仅 Android：状态栏明暗。 */
	isBright?: boolean;
	/** 仅 Android：显示关闭按钮。 */
	showCloseButton?: boolean;
	actionTxt?: string;
	/** 原生尚不支持，传入会拒绝。 */
	actionIcon?: string;
	actionExt?: string;
	/** 函数仅留在当前文档；局部外观更新保留现有 handler。 */
	onActionClick?: (data: { actionExt?: string }) => void;
	/** 原生尚不支持，传入会拒绝。 */
	translucentStatusBars?: boolean;
};

export type ParamPhoneCall = {
	phoneNumber: string;
};

export type ParamScanCode = {
	/**
	* 扫码类型：qrCode 为二维码，barCode 为条形码。省略时识别两类。
	**/
	scanType?: ScanType[];
	/**
	* 是否隐藏相册。省略时 iOS 显示、Android 隐藏；显式传入 false 可选图识别。
	**/
	hideAlbum?: boolean;
	/**
	* 兼容字段，目前不自定义系统相机权限提示标题。
	**/
	permissionPromptTitle?: string;
	/**
	* 兼容字段，目前不自定义系统相机权限提示内容。
	**/
	permissionPromptMessage?: string;
};

export type ParamImageToPhotosAlbum = {
	/**
	* 图片 base64
	**/
	base64Image: string;
	/**
	* 权限提示 标题 用于Android 提示
	**/
	permissionPromptTitle?: string;
	/**
	* 权限提示内容 用于Android 提示
	**/
	permissionPromptMessage?: string;
};
interface ExtendInfo { }
export type ReturnAppInfo = {
	/**
	* 应用 appid
	**/
	appId: string;
	/**
	* 版本信息
	**/
	appVersionName: string;
	/**
	* 内部版本号
	**/
	appVersionCode: number;
	/**
	* 环境 0:测试环境 1:预生产环境 2:生产环境
	**/
	environment: number;
	/**
	* 扩展信息字段
	**/
	extendInfo?: ExtendInfo;
};

export type ReturnDeviceInfo = {
	/**
	* 1:Android 2:iOS
	**/
	osType: number;
	/**
	* 设备系统版本
	**/
	osVersion: string;
	/**
	* 设备型号
	**/
	model: string;
	/**
	* 设备品牌
	**/
	brand: string;
	/**
	* 设备id
	**/
	deviceId: string;
	/**
	* 状态栏高度
	**/
	statusBarHeight: number;
	/**
	* 底部安全区域高度
	**/
	bottomSafeAreaHeight: number;
};
export type ReturnNetworkType = {
	networkType: NetworkStatus;
};

export type ReturnScanCode = {
	scanType: ScanType;
	code: string;
};

export type ReturnNotiSwitchStatus = {
	status: boolean;
};

export type GenericCallbackFunc<T = any> = (data: T) => void;

export type CallbackNetworkStatusChange = {
	networkType: NetworkStatus;
};


export type ParamCompressImage = {
	/**
	* 图片base64
	**/
	base64Image: string;
	/**
	* 压缩之后最大文件大小 (字节)
	**/
	maxLength?: number;
};
export type ReturnCompressImageResult = {
	/**
	* 图片base64
	**/
	base64Image: string;
	/**
	* 图片宽度
	**/
	imageWidth?: number
	/**
	* 图片高度
	**/
	imageHeight?: number
};

export type ChooseImageSizeType = "original" | "compressed";
export type ChooseImageSourceType = "album" | "camera" | "all";
export type ParamChooseImage = {
	/**
	* 图片来源 album:相册 camera:相机 all:弹出选择框 来选择相册还是相机
	**/
	sourceType: ChooseImageSourceType;
	/**
	* 图片尺寸类型 original:原始尺寸 compressed:压缩尺寸
	**/
	sizeType?: ChooseImageSizeType[];
	/**
	* 图片数量
	**/
	count?: number;
	/**
	* 权限提示 标题 用于Android 提示
	**/
	permissionPromptTitle?: string;
	/**
	* 权限提示内容 用于Android 提示
	**/
	permissionPromptMessage?: string;
};

export type ReturnImageDataResult = {
	/**
	* 原始图片 路径
	**/
	original: string;
	/**
* 压缩图片 路径
**/
	compressed: string;
};
export type ReturnChooseImageResult = {
	data: ReturnImageDataResult[];
};

export type ParamOpenFileInfo = {
	//文件地址
	url: string;
	//fileName 必须包含后缀 . 为空时从url里截取
	fileName?: string;
};
export type ParamConvertImagePathToBase64 = {
	/**
	 * 图片路径
	 **/
	path: string;
};
export type ReturnConvertImagePathToBase64Result = {

	/**
	 * 图片 base64
	 **/
	base64Image?: string;
};
export type ParamOpenAppPage = {
	pageName: string;
	extInfo?: any
};

export type ReturnPermissionResult = {
	grant: boolean;
};
export type ParamCheckRequestCameraPermissions = {
	/**
	* 权限提示 标题 用于Android 提示
	**/
	permissionPromptTitle?: string;
	/**
	* 权限提示内容 用于Android 提示
	**/
	permissionPromptMessage?: string;
};



export interface MWBJSSDK {
	/** 当前主文档首屏已准备好；重复调用幂等，不代表宿主展示动画已完成。 */
	notifyPageReady(): Promise<GenericAsyncResult<void>>;
	version: TYPE_VERSION;
	//设置是否打开调试开关。
	setEnableDebug(enableDebug: boolean): void;
	/**
	 * 跳转当前App的系统授权管理⻚
	 **/
	openAppAuthorizeSetting(): Promise<GenericAsyncResult<undefined>>;
	/**
	 * Toast
	 **/
	toast(param: ParamToast): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 获取当前App相关信息
	 **/
	getAppInfoSync(): ReturnAppInfo;
	/**
	 * 在App应用图标上显示数字⻆标
	 **/
	setBadgeCount(param: ParamBadgeCount): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 打开新页面
	 **/
	navigateTo(param: ParamNavigateTo): Promise<GenericAsyncResult<undefined>>;
	/** 替换当前容器，返回时跳过被替换页；不要依赖旧页在成功后继续执行 JS。 */
	redirectTo(param: ParamRedirectTo): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 返回上一级
	 *
	 **/
	navigateBack(callbackInfo?: Record<string, any>): Promise<GenericAsyncResult<undefined>>;
	/**
		 * 返回到首页
		 *
		 **/
	navigateBackToRoot(): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 用外部浏览器打开⻚面
	 **/
	openExternalBrowser(param: ParamExternalBrowse): Promise<GenericAsyncResult<undefined>>;

	/**
	 * 设置WebView容器⻚面的导航栏主题
	 **/
	setNavigationBarTheme(param: ParamNavigationBarTheme): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 获取设备相关信息
	 **/
	getDeviceInfoSync(): ReturnDeviceInfo;

	/**
	 * 获取系统剪贴板的内容
	 **/
	getClipboardDataSync(): ClipboardData;
	/**
	 * 设置系统剪贴板的内容
	 **/
	setClipboardData(param: ClipboardData): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 拨打电话
	 **/
	makePhoneCall(param: ParamPhoneCall): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 获取设备网络状态
	 **/
	getNetworkTypeSync(): ReturnNetworkType;
	/**
	 * 获取推送权限开关状态
	 **/
	getNotificationSwitchStatus(): Promise<GenericAsyncResult<ReturnNotiSwitchStatus>>;


	/**
	 * 清理webview缓存
	 **/
	cleanWebviewCache(): Promise<GenericAsyncResult<undefined>>;
	/**
	 * 压缩图片
	 **/
	compressImage(param: ParamCompressImage): Promise<GenericAsyncResult<ReturnCompressImageResult>>;
	/**
	 * 扫码
	 **/
	scanCode(param: ParamScanCode): Promise<GenericAsyncResult<ReturnScanCode>>;
	/**
	 * 保存图片到相册
	 **/
	saveImageToPhotosAlbum(param: ParamImageToPhotosAlbum): Promise<GenericAsyncResult<undefined>>;

	/**
	 * 选择照片
	 **/
	chooseImage(param: ParamChooseImage): Promise<GenericAsyncResult<ReturnChooseImageResult>>;

	/**
	 * 同步存储
	 **/
	setStorageSync(key: string, data: any, groupName?: string, validSecond?: number): void;

	/**
	 * 异步存储
	 **/
	// setStorage(param: ParamStorage): Promise<GenericAsyncResult<undefined>>;

	/**
	 * 同步获取存储
	 **/

	getStorageSync<T>(key: string, groupName?: string): T | undefined;

	/**
	 * 异步获取存储
	 **/
	// getStorage(param: ParamStorage): Promise<GenericAsyncResult<ReturnStorageResult>>;
	/**
	 * 同步移除存储
	 **/
	removeStorageSync(key: string, groupName?: string): void;
	/**
	 * 移除存储
	 **/
	// removeStorage(param: ParamRemoveStorage): Promise<GenericAsyncResult<undefined>>;

	/**
		 * 同步清除存储
		 **/
	clearStorageSync(groupName?: string): void;
	/**
	 * 清除存储
	 **/
	// clearStorage(param?: ParamStorageClear): Promise<GenericAsyncResult<undefined>>;

	/**
	 * 打开PDF文件
	 **/
	openFile(param?: ParamOpenFileInfo): Promise<GenericAsyncResult<undefined>>;

	/**
		 * 退出APP
		 **/
	exitApp(): Promise<GenericAsyncResult<undefined>>;

	/**
		 * 检查是否有相机权限
		 **/
	checkRequestCameraPermissions(param?: ParamCheckRequestCameraPermissions): Promise<GenericAsyncResult<ReturnPermissionResult>>;


	/**
	 * 本地图片path 转 base64
	**/
	convertImagePathToBase64(param?: ParamConvertImagePathToBase64): Promise<GenericAsyncResult<ReturnConvertImagePathToBase64Result>>;

	/**
		* 跳转App原生界面
		**/
	openNativePage(param: ParamOpenAppPage): Promise<GenericAsyncResult<undefined>>;


	/**
	 * H5 注册一个句柄,提供给Native调用
	 **/
	registerHandler(handlerName: string, handler: GenericCallbackFunc): void;
	/**
	 * 解绑某个handleName下的所有句柄
	 **/
	unRegisterHandlers(handlerName: string): void;
	/**
	 * 解绑句柄
	 **/
	unRegisterHandler(handlerName: string, handler: GenericCallbackFunc): void;

	/**
	 * 检查 H5 是否已经注册句柄。native内部会调用
	 **/
	checkHandlerExist(handlerName: string): boolean;

	/**
	 * 监听网络状态变化
	 **/
	onNetworkStatusChange(handler: GenericCallbackFunc<CallbackNetworkStatusChange>): void;

	/**
	 * 移除监听网络状态变化
	 **/
	offNetworkStatusChange(handler: GenericCallbackFunc<CallbackNetworkStatusChange>): void;

	/**
	 * 监听App切前台事件
	 **/
	onAppShow(handler: GenericCallbackFunc<void>): void;
	/**
	 * 移除监听App切前台事件
	 **/
	offAppShow(handler: GenericCallbackFunc<void>): void;
	/**
	 * 监听App切后台台事件
	 **/
	onAppHide(handler: GenericCallbackFunc<void>): void;
	/**
	 * 移除监听App切后台事件
	 **/
	offAppHide(handler: GenericCallbackFunc<void>): void;
	/**
	 * 监听App Push Notification事件
	 **/
	onRemoteNotificationReceive(handler: GenericCallbackFunc<void>): void;
	/**
	 * 移除App Push Notification事件
	 **/
	offRemoteNotificationReceive(handler: GenericCallbackFunc<void>): void;

	/**
	 * 监听Page显示事件
	 **/
	onPageShow(handler: GenericCallbackFunc<void>): void;
	/**
	 * 移除监听Page显示事件
	 **/
	offPageShow(handler: GenericCallbackFunc<void>): void;
	/**
	 * 监听Page消失事件
	 **/
	onPageHide(handler: GenericCallbackFunc<void>): void;
	/**
	 * 移除监听Page消失事件
	 **/
	offPageHide(handler: GenericCallbackFunc<void>): void;
	/**
		* 监听物理返回按钮点击事件
		**/
	onBackBtnPressed(handler: () => boolean): void;
	/**
		* 取消监听物理返回按钮点击事件
		**/
	offBackBtnPressed(): void;
}
