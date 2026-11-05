import { callAsync, callSync } from "../bridge";
import type { MWBJSSDK } from "../types";

/** 应用、设备及系统设置能力。 */
export const devicePlugin = {
  name: "device",
  methods: {
    openAppAuthorizeSetting() { return callAsync("openAppAuthorizeSetting"); },
    getAppInfoSync() { return callSync("getAppInfoSync"); },
    setBadgeCount(param) { return callAsync("setBadgeCount", param); },
    getDeviceInfoSync() { return callSync("getDeviceInfoSync"); },
    getClipboardDataSync() { return callSync("getClipboardDataSync"); },
    setClipboardData(param) { return callAsync("setClipboardData", param); },
    makePhoneCall(param) { return callAsync("makePhoneCall", param); },
    getNetworkTypeSync() { return callSync("getNetworkTypeSync"); },
    getNotificationSwitchStatus() { return callAsync("getNotificationSwitchStatus"); }
  } satisfies Pick<MWBJSSDK,
    "openAppAuthorizeSetting" | "getAppInfoSync" | "setBadgeCount" |
    "getDeviceInfoSync" | "getClipboardDataSync" | "setClipboardData" |
    "makePhoneCall" | "getNetworkTypeSync" | "getNotificationSwitchStatus">
} as const;
