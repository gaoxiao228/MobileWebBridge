import { callAsync, callSync } from "../bridge";
import { notifyPageReady } from "../nativePlugins";
import type { MWBJSSDK } from "../types";

/** Web 容器和页面导航能力。 */
export const containerPlugin = {
  name: "container",
  methods: {
    notifyPageReady,
    setEnableDebug(enabled) { callSync("setEnableDebug", { enabled }); },
    toast(param) { return callAsync("toast", param); },
    navigateTo(param) { return callAsync("navigateTo", param); },
    navigateBack(callbackInfo) { return callAsync("navigateBack", callbackInfo); },
    navigateBackToRoot() { return callAsync("navigateBackToRoot"); },
    openExternalBrowser(param) { return callAsync("openExternalBrowser", param); },
    setNavigationBarTheme(param) { return callAsync("setNavigationBarTheme", param); },
    cleanWebviewCache() { return callAsync("cleanWebviewCache"); },
    exitApp() { return callAsync("exitApp"); },
    openNativePage(param) { return callAsync("openNativePage", param); }
  } satisfies Pick<MWBJSSDK,
    "notifyPageReady" | "setEnableDebug" | "toast" | "navigateTo" | "navigateBack" |
    "navigateBackToRoot" | "openExternalBrowser" | "setNavigationBarTheme" |
    "cleanWebviewCache" | "exitApp" | "openNativePage">
} as const;
