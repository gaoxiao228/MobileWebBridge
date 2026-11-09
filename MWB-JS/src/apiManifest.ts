// 公共方法清单用于校验 JS、iOS 和 Android 的能力覆盖。
import type { MWBJSSDK } from "./types";

export const apiMethods = [
  "notifyPageReady",
  "setEnableDebug", "openAppAuthorizeSetting", "toast", "getAppInfoSync",
  "setBadgeCount", "navigateTo", "redirectTo", "navigateBack", "navigateBackToRoot",
  "openExternalBrowser", "setNavigationBarTheme", "getDeviceInfoSync", "getClipboardDataSync",
  "setClipboardData", "makePhoneCall", "getNetworkTypeSync", "getNotificationSwitchStatus",
  "cleanWebviewCache", "compressImage", "scanCode", "saveImageToPhotosAlbum",
  "chooseImage", "setStorageSync", "getStorageSync", "removeStorageSync",
  "clearStorageSync", "openFile", "exitApp", "checkRequestCameraPermissions",
  "convertImagePathToBase64", "openNativePage", "registerHandler",
  "unRegisterHandlers", "unRegisterHandler", "checkHandlerExist", "onNetworkStatusChange",
  "offNetworkStatusChange", "onAppShow", "offAppShow", "onAppHide",
  "offAppHide", "onRemoteNotificationReceive", "offRemoteNotificationReceive", "onPageShow",
  "offPageShow", "onPageHide", "offPageHide", "onBackBtnPressed",
  "offBackBtnPressed",
] as const satisfies readonly (keyof MWBJSSDK)[];
