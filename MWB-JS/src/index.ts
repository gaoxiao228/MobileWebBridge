/** 默认入口组合全部能力，同时保留按功能组合的构造函数。 */
import "dsbridge";
export { createMWB, defineNativePlugin } from "./createMWB";
export type { MWBPlugin, MWBNativePlugin, MWBClient, MWBSDK, MWBBasic } from "./createMWB";
export { MWBBridgeError } from "./bridge";
export * from "./types";
export { containerPlugin } from "./plugins/container";
export { devicePlugin } from "./plugins/device";
export { mediaPlugin } from "./plugins/media";
export { storagePlugin } from "./plugins/storage";
export { basicPlugin } from "./plugins/basic";

import { createMWB } from "./createMWB";
import type { MWBClient } from "./createMWB";

declare global {
  interface Window {
    mwb: MWBClient;
  }
}

export const mwb = createMWB();
export default mwb;
