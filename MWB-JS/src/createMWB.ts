import { assembleMWB, type MWBPlugin, type MWBSDK, type MWBPartialSDK } from "./assembleMWB";
import { attachNativePlugins, hasNativePlugin, type MWBNativePlugin, type NativePluginNamespaces } from "./nativePlugins";
import { containerPlugin } from "./plugins/container";
import { devicePlugin } from "./plugins/device";
import { mediaPlugin } from "./plugins/media";
import { storagePlugin } from "./plugins/storage";

export type { MWBPlugin } from "./assembleMWB";
export type { MWBSDK, MWBBasic } from "./assembleMWB";
export { defineNativePlugin } from "./nativePlugins";
export type { MWBNativePlugin } from "./nativePlugins";

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
