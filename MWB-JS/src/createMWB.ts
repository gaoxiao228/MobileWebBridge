import { assembleMWB, type MWBPlugin, type MWBSDK, type MWBPartialSDK } from "./assembleMWB.js";
import { attachNativePlugins, hasNativePlugin, type MWBNativePlugin, type NativePluginNamespaces } from "./nativePlugins.js";
import { containerPlugin } from "./plugins/container.js";
import { devicePlugin } from "./plugins/device.js";
import { mediaPlugin } from "./plugins/media.js";
import { storagePlugin } from "./plugins/storage.js";

export type { MWBPlugin } from "./assembleMWB.js";
export type { MWBSDK, MWBBasic } from "./assembleMWB.js";
export { defineNativePlugin } from "./nativePlugins.js";
export type { MWBNativePlugin } from "./nativePlugins.js";

export type MWBClient = MWBSDK & { hasPlugin(name: string): Promise<boolean> };

const defaultPlugins: MWBPlugin[] = [containerPlugin, devicePlugin, mediaPlugin, storagePlugin];

export function createMWB(): MWBClient;
export function createMWB<const Plugins extends readonly MWBNativePlugin[]>(options: { plugins: Plugins }): MWBClient & NativePluginNamespaces<Plugins>;
export function createMWB(plugins: MWBPlugin[]): MWBPartialSDK;
export function createMWB(input: MWBPlugin[] | { plugins: readonly MWBNativePlugin[] } = defaultPlugins): MWBPartialSDK {
  const sdk = assembleMWB(Array.isArray(input) ? input : defaultPlugins);
  // Core 查询不影响旧 basic 桥调用；旧数组裁剪入口也可按需查询宿主插件。
  Object.assign(sdk, { hasPlugin: hasNativePlugin });
  if (!Array.isArray(input)) attachNativePlugins(sdk, input.plugins);
  return sdk;
}
