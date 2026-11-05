import { expect, test } from "vitest";
import { apiMethods } from "../src/apiManifest";
import type { MWBJSSDK } from "../src/types";

// 这个清单来自用户提供的接口基准，防止公开方法被遗漏或意外改名。
const expectedMethods = [
  "notifyPageReady",
  "setEnableDebug", "openAppAuthorizeSetting", "toast", "getAppInfoSync",
  "setBadgeCount", "navigateTo", "navigateBack", "navigateBackToRoot",
  "openExternalBrowser", "setNavigationBarTheme", "getDeviceInfoSync",
  "getClipboardDataSync", "setClipboardData", "makePhoneCall",
  "getNetworkTypeSync", "getNotificationSwitchStatus", "cleanWebviewCache",
  "compressImage", "scanCode", "saveImageToPhotosAlbum", "chooseImage",
  "setStorageSync", "getStorageSync", "removeStorageSync", "clearStorageSync",
  "openFile", "exitApp", "checkRequestCameraPermissions",
  "convertImagePathToBase64", "openNativePage", "registerHandler",
  "unRegisterHandlers", "unRegisterHandler", "checkHandlerExist",
  "onNetworkStatusChange", "offNetworkStatusChange", "onAppShow",
  "offAppShow", "onAppHide", "offAppHide", "onRemoteNotificationReceive",
  "offRemoteNotificationReceive", "onPageShow", "offPageShow", "onPageHide",
  "offPageHide", "onBackBtnPressed", "offBackBtnPressed"
] as const satisfies readonly (keyof MWBJSSDK)[];

test("MWB exposes the 49 current methods", () => {
  expect(apiMethods).toEqual(expectedMethods);
});

// 编译检查同步清空存储只接收可选分组名。
type ClearStorageSignature = MWBJSSDK["clearStorageSync"];
const clearStorage: ClearStorageSignature = (_groupName?: string) => {};
void clearStorage;
