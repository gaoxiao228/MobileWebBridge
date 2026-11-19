/** 默认入口组合全部能力，同时保留按功能组合的构造函数。 */
import "dsbridge";
export { createMWB, defineNativePlugin } from "./createMWB.js";
export type { MWBPlugin, MWBNativePlugin, MWBClient, MWBSDK, MWBBasic } from "./createMWB.js";
export { MWBBridgeError } from "./bridge.js";
export * from "./types.js";
export { containerPlugin } from "./plugins/container.js";
export { devicePlugin } from "./plugins/device.js";
export { mediaPlugin } from "./plugins/media.js";
export { storagePlugin } from "./plugins/storage.js";
export { basicPlugin } from "./plugins/basic.js";

import { createMWB } from "./createMWB.js";
import type { MWBClient } from "./createMWB.js";

declare global {
  interface Window {
    mwb: MWBClient;
  }
}

export const mwb = createMWB();
export default mwb;
