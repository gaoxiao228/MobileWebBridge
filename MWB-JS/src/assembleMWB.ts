import { version, type MWBJSSDK, type ParamNavigationBarTheme } from "./types";
import { createEvents } from "./events";

/** 插件描述只包含所选功能，供浏览器组合包静态裁剪。 */
export interface MWBPlugin {
  readonly name: string;
  readonly methods: Record<string, (...args: never[]) => unknown>;
}

/** basic 的根兼容入口与命名空间始终共享同一份函数和事件状态。 */
export type MWBBasic = Omit<MWBJSSDK, "version">;
export type MWBSDK = MWBJSSDK & { readonly basic: MWBBasic };
export type MWBPartialSDK = Partial<MWBJSSDK> & { readonly basic: Partial<MWBBasic> };

export function assembleMWB(plugins: MWBPlugin[]): MWBPartialSDK {
  const events = createEvents();
  // 旧数组组合不得覆盖 Core、事件状态或对象原型成员。
  const protectedNames = new Set(["basic", "version", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin", "pluginEvent", "constructor", "prototype", "__proto__", ...Object.keys(events)]);
  const methods: Record<string, (...args: never[]) => unknown> = Object.create(null);
  const selected = new Set<MWBPlugin>();
  for (const plugin of plugins) {
    if (selected.has(plugin)) continue;
    selected.add(plugin);
    for (const [name, method] of Object.entries(plugin.methods)) {
      if (protectedNames.has(name)) throw new Error(`Reserved MWB basic method: ${name}`);
      if (Object.prototype.hasOwnProperty.call(methods, name)) throw new Error(`Duplicate MWB basic method: ${name}`);
      methods[name] = method;
    }
  }
  const nativeSetTheme = methods.setNavigationBarTheme as
    ((param: Omit<ParamNavigationBarTheme, "onActionClick">) => ReturnType<MWBJSSDK["setNavigationBarTheme"]>) | undefined;
  if (nativeSetTheme) {
    let currentActionClick: ((data: { actionExt?: string }) => void) | undefined;
    // 串行提交使原生样式与 JS 回调按调用顺序一起生效；拒绝不会阻断后续补丁。
    let themeQueue: Promise<unknown> = Promise.resolve();
    methods.setNavigationBarTheme = async (param: ParamNavigationBarTheme) => {
      // DSBridge 会序列化参数；回调留在当前 SDK 实例，原生只接收按钮配置。
      const { onActionClick, ...nativeParam } = param;
      if (onActionClick !== undefined && typeof onActionClick !== "function") {
        throw new TypeError("onActionClick must be a function");
      }
      const request = themeQueue.then(async () => {
        const result = await nativeSetTheme(nativeParam);
        const clearsAction = typeof nativeParam.actionTxt === "string" && !nativeParam.actionTxt.trim();
        if (clearsAction || onActionClick !== undefined) {
          if (currentActionClick) events.unRegisterHandler("navigationActionClick", currentActionClick);
          currentActionClick = clearsAction ? undefined : onActionClick;
          if (currentActionClick) events.registerHandler("navigationActionClick", currentActionClick);
        }
        return result;
      });
      themeQueue = request.catch(() => undefined);
      return request;
    };
  }
  const basic = Object.freeze({ ...methods, ...events });
  return { version, ...basic, basic } as MWBPartialSDK;
}
