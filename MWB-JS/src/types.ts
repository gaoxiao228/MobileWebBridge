// MWB 的公开契约以用户提供的旧 JS SDK 类型为基准，版本和产品命名已更新。
export const version = "0.1.4";

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


/** 替换当前原生容器；Android 必须省略 waitForReady，不支持创建新弹窗。 */
export type ParamRedirectTo = {
	/** 目标地址，沿用容器的可信来源限制。 */
	url: string;
	/** 新容器标题。 */
	title?: string;
	/** 是否隐藏导航栏，默认 true。 */
	hidden?: boolean;
	/** 仅 iOS：等待主文档加载和绘制准备，默认 false；最多 3000ms，失败保留当前页。 */
	waitForReady?: boolean;
};

export type ParamNavigateTo = {
	/** 仅 iOS：SDK 等待主文档加载与绘制准备后转场，默认 false；最长等待 3000ms，不代表业务数据就绪。 */
	waitForReady?: boolean;
	/**
	* 跳转地址
	**/
	url: string;
	/**
	* 是否隐藏导航栏，默认 true
	**/
	hidden?: boolean;
	/**
	* 导航栏标题
	**/
	title?: string;
	/**
	*  标题文字颜色，如 eeeeee
	**/
	titleColor?: string;
	/**
	* 导航栏颜色 如 eeeeee
	**/
	color?: string;
	/**
	* 是否是亮色主题 控制状态栏
	**/
	isBright?: boolean;
	/**
	* 是否显示返回按钮
	**/
	showBackButton?: boolean;
	/**
	* 是否显示关闭按钮
	**/
	showCloseButton?: boolean;
	/**
	* 右上角文字按钮
	**/
	actionTxt?: string;
	/**
	* 右上角 icon base64
	**/
	actionIcon?: string;
	/**
	* 右上角 传参 点击的时候会回传给H5
	**/
	actionExt?: string;
	/**
	* 状态栏是否沉浸
	**/
	translucentStatusBars?: boolean;
	/**
	* 打开新页面样式是否弹出
	**/
	isPopUp?: boolean;
	/**
	* 打开的新页面回调给当前页面的回调函数
	**/
	callbackFunction?: GenericCallbackFunc | string;

};

export type ParamExternalBrowse = {
	url: string;
};

export type ParamNavigationBarTheme = {
	/**
	* 是否隐藏导航栏
	**/
	hidden?: boolean;
	/**
	* 导航栏标题
	**/
	title?: string;
	/**
	*  标题文字颜色，如 eeeeee
	**/
	titleColor?: string;
	/**
	* 导航栏颜色 如 eeeeee
	**/
	color?: string;
	/**
	* 是否是亮色主题 控制状态栏
	**/
	isBright?: boolean;
	/**
	* 是否显示返回按钮
	**/
	showBackButton?: boolean;
	/**
	* 是否显示关闭按钮
	**/
	showCloseButton?: boolean;
	/**
	* 右上角文字按钮
	**/
	actionTxt?: string;
	/**
	* 右上角 icon base64
	**/
	actionIcon?: string;
	/**
	* 右上角 传参 点击的时候会回传给H5
	**/
	actionExt?: string;
	/** 当前页面右上角文字按钮被点击时执行；函数只由 JS SDK 保存。 */
	onActionClick?: (data: { actionExt?: string }) => void;
	/**
	* 状态栏是否沉浸
	**/
	translucentStatusBars?: boolean;
};

export type ParamPhoneCall = {
	phoneNumber: string;
};

export type ParamScanCode = {
	/**
	* 扫码类型  qrCode:二维码 barCode:条形码
	**/
	scanType?: ScanType[];
	/**
	* 是否隐藏相册按钮 如果不隐藏,则可以通过选择相册里的二维码识别
	**/
	hideAlbum?: boolean;
	/**
	* 权限提示 标题 用于Android 提示
	**/
	permissionPromptTitle?: string;
	/**
	* 权限提示内容 用于Android 提示
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
