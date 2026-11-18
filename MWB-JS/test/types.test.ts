import { expect, test } from "vitest";
import { apiMethods } from "../src/apiManifest";
import type { MWBJSSDK, ParamNavigateTo, ParamRedirectTo, ParamNavigationBarTheme, NavigationBarAppearanceOptions } from "../src/types";

// 这个清单来自用户提供的接口基准，防止公开方法被遗漏或意外改名。
const expectedMethods = [
  "notifyPageReady",
  "setEnableDebug", "openAppAuthorizeSetting", "toast", "getAppInfoSync",
  "setBadgeCount", "navigateTo", "redirectTo", "navigateBack", "navigateBackToRoot",
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

test("MWB exposes the 50 current methods", () => {
  expect(apiMethods).toEqual(expectedMethods);
});

// 编译检查同步清空存储只接收可选分组名。
type ClearStorageSignature = MWBJSSDK["clearStorageSync"];
const clearStorage: ClearStorageSignature = (_groupName?: string) => {};
void clearStorage;

// iOS 自动绘制准备是可选布尔值，旧调用仍可省略。
const preparedNavigation = { url: "https://example.com", waitForReady: true } satisfies ParamNavigateTo;
void preparedNavigation;

// 替换参数使用独立类型，不接受打开新弹窗这一相反语义。
const replacement = { url: "https://example.com/b", waitForReady: true } satisfies ParamRedirectTo;
void replacement;

// 编译约束：三个入口共享同一组外观字段，旧调用仍可省略。
const appearance = { color: "f6fbfa", titleColor: "0b4148", buttonColor: "049f91", backButtonStyle: "arrowText",
  backButtonText: "返回", showBackButton: true, separatorVisible: true, separatorColor: "dfe8e5",
  titleFontSize: 17, titleFontWeight: "semibold", buttonFontSize: 16 } satisfies NavigationBarAppearanceOptions;
const styledPush = { url: "https://example.com/a", ...appearance } satisfies ParamNavigateTo;
const styledReplace = { url: "https://example.com/b", ...appearance } satisfies ParamRedirectTo;
const styledUpdate = { ...appearance } satisfies ParamNavigationBarTheme;
void styledPush; void styledReplace; void styledUpdate;
