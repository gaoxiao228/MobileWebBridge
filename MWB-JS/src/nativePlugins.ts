import { apiMethods } from "./apiManifest";
import { getBridge, MWBBridgeError, type DSBridgeLike } from "./bridge";
import { getEventHub } from "./eventHub";
import type { GenericAsyncResult } from "./types";

const descriptorBrand = Symbol("MWBNativePlugin");
const reserved = new Set<string>([...apiMethods, "basic", "version", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin", "pluginEvent", "dispatchEvent", "backBtnPressed", "on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__"]);
const methodReserved = new Set(["on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__"]);
type AsyncMethods<T> = { [K in keyof T]: (params: never) => Promise<GenericAsyncResult<unknown>> };
type ReservedMethod = "on" | "then" | "catch" | "finally" | "toJSON" | "inspect" | "constructor" | "prototype" | "__proto__";
type SafeMethods<T> = Extract<keyof T, ReservedMethod> extends never ? unknown : { readonly __reservedMethod: never };

/** 描述只含插件名和超时配置；方法与事件泛型不生成额外运行时清单。 */
export interface MWBNativePlugin<Name extends string = string, Methods = unknown, Events = unknown> {
  readonly name: Name;
  readonly timeoutMs: number;
  readonly [descriptorBrand]: true;
  readonly __types?: { methods: Methods; events: Events };
}

export type NativePluginAPI<Methods, Events> = Methods & {
  on<K extends keyof Events & string>(name: K, handler: (data: Events[K]) => void): () => void;
};
export type NativePluginNamespaces<Plugins extends readonly MWBNativePlugin[]> = {
  readonly [P in Plugins[number] as P["name"]]: P extends MWBNativePlugin<string, infer Methods, infer Events>
    ? NativePluginAPI<Methods, Events> : never;
};

function validName(name: unknown): name is string {
  return typeof name === "string" && /^[a-z][a-zA-Z0-9_]*$/.test(name);
}

/** 先指定业务类型，再让插件配置保留名字面量。 */
export function defineNativePlugin<Methods extends AsyncMethods<Methods>, Events = Record<never, never>>() {
  return <const Name extends string>(options: { name: Name; timeoutMs?: number } & SafeMethods<Methods>): MWBNativePlugin<Name, Methods, Events> => {
    if (!validName(options.name) || reserved.has(options.name)) throw new Error(`Invalid or reserved MWB plugin name: ${options.name}`);
    const timeoutMs = options.timeoutMs ?? 30000;
    if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120000) throw new Error("MWB timeoutMs must be an integer from 1 to 120000");
    return Object.freeze({ name: options.name, timeoutMs, [descriptorBrand]: true as const });
  };
}

/** 拒绝会被 JSON 静默丢弃或改变的参数，而不是让支付等业务收到残缺数据。 */
function assertJSON(value: unknown, ancestors = new Set<object>()): void {
  if (value === null || typeof value === "string" || typeof value === "boolean") return;
  if (typeof value === "number" && Number.isFinite(value)) return;
  if (typeof value !== "object" || value === null || ancestors.has(value)) throw new MWBBridgeError(-1102, "Plugin data must be finite, acyclic JSON");
  const prototype = Object.getPrototypeOf(value);
  if (!Array.isArray(value) && prototype !== Object.prototype && prototype !== null) throw new MWBBridgeError(-1102, "Plugin data must contain plain JSON objects");
  if (Object.getOwnPropertySymbols(value).length) throw new MWBBridgeError(-1102, "Symbol properties are not JSON data");
  // 校验过程不能执行 getter；否则序列化时可能得到与已校验数据不同的业务参数。
  if (Object.values(Object.getOwnPropertyDescriptors(value)).some(property => property.get || property.set)) {
    throw new MWBBridgeError(-1102, "Plugin data must not contain accessors");
  }
  ancestors.add(value);
  const values = Array.isArray(value) ? Array.from(value) : Object.values(value);
  for (const child of values) assertJSON(child, ancestors);
  ancestors.delete(value);
}

function envelope<T>(value: unknown): GenericAsyncResult<T> {
  if (typeof value === "string") {
    try { value = JSON.parse(value); } catch { throw new MWBBridgeError(-1102, "Invalid plugin response JSON"); }
  }
  if (!value || typeof value !== "object" || !("errCode" in value) || !Number.isInteger(value.errCode)) throw new MWBBridgeError(-1102, "Invalid plugin response");
  const response = value as GenericAsyncResult<T>;
  if (response.errCode !== 0) throw new MWBBridgeError(response.errCode, response.errorMsg ?? "MWB plugin call failed");
  if ("result" in response) assertJSON(response.result);
  return response;
}

type Session = { protocol: 1; documentId: string };
function session(bridge: DSBridgeLike): Session {
  if (bridge.hasNativeMethod && !bridge.hasNativeMethod("mwb.pluginSession", "syn")) throw new MWBBridgeError(-1106, "This app does not support MWB native plugins");
  let value: unknown;
  try { value = bridge.call("mwb.pluginSession"); }
  catch (error) { throw new MWBBridgeError(-1106, error instanceof Error ? error.message : "Plugin session unavailable"); }
  if (value === undefined || value === null || value === "") throw new MWBBridgeError(-1106, "This app does not support MWB native plugins");
  const info = envelope<Session>(value).result;
  if (info?.protocol !== 1 || typeof info.documentId !== "string" || !info.documentId) throw new MWBBridgeError(-1106, "Incompatible MWB plugin protocol");
  return info;
}

let nextCall = 0;
function invoke<T>(gateway: string, payload: Record<string, unknown>, timeoutMs: number): Promise<GenericAsyncResult<T>> {
  return new Promise((resolve, reject) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let finished = false;
    const complete = (value?: unknown, error?: unknown) => {
      if (finished) return;
      finished = true;
      if (timer !== undefined) clearTimeout(timer);
      try {
        if (error) throw error;
        resolve(envelope<T>(value));
      } catch (failure) {
        reject(failure instanceof MWBBridgeError ? failure : new MWBBridgeError(-1105, failure instanceof Error ? failure.message : String(failure)));
      }
    };
    try {
      const bridge = getBridge();
      const identity = session(bridge);
      if (bridge.hasNativeMethod && !bridge.hasNativeMethod(gateway, "asyn")) throw new MWBBridgeError(-1106, "Plugin gateway unavailable in this app");
      timer = setTimeout(() => complete(undefined, new MWBBridgeError(-1103, "MWB plugin call timed out")), timeoutMs);
      bridge.call(gateway, { ...identity, ...payload }, value => complete(value));
    } catch (error) { complete(undefined, error); }
  });
}

/** 只查询原生注册，不把本地 JS 描述误报成已安装能力。 */
export async function hasNativePlugin(name: string): Promise<boolean> {
  if (!validName(name)) throw new MWBBridgeError(-1102, "Invalid plugin name");
  const value = await invoke<{ available: boolean }>("mwb.pluginInfo", { plugin: name }, 30000);
  if (typeof value.result?.available !== "boolean") throw new MWBBridgeError(-1102, "Invalid plugin availability response");
  return value.result.available;
}

/** 内置首屏通知复用插件身份与有界等待，不通过普通 basic 通道跨文档投递。 */
export function notifyPageReady(): Promise<GenericAsyncResult<void>> {
  return invoke<void>("mwb.invokePlugin", {
    plugin: "basic", method: "notifyPageReady", params: null,
    callId: `mwb-${Date.now()}-${++nextCall}`, timeoutMs: 30000
  }, 30000);
}

function createNamespace(descriptor: MWBNativePlugin): object {
  const functions = new Map<string, unknown>();
  const on = (name: string, handler: (data: unknown) => void) => {
    if (!validName(name) || methodReserved.has(name) || typeof handler !== "function") throw new MWBBridgeError(-1102, "Invalid plugin event subscription");
    const bridge = getBridge();
    const identity = session(bridge);
    return getEventHub(bridge).on("mwb.pluginEvent", (value: unknown) => {
      if (!value || typeof value !== "object") return;
      const event = value as Record<string, unknown>;
      if (event.plugin === descriptor.name && event.name === name && event.documentId === identity.documentId) {
        assertJSON(event.data);
        handler(event.data);
      }
    });
  };
  return new Proxy(Object.create(null) as object, {
    get(_target, property) {
      if (property === "on") return on;
      // Promise、JSON、开发工具和原型探测不能被误识别成业务调用。
      if (!validName(property) || methodReserved.has(property)) return undefined;
      if (!functions.has(property)) functions.set(property, (...args: unknown[]) => {
        try {
          if (args.length > 1) throw new MWBBridgeError(-1102, "Plugin methods accept one JSON parameter");
          const params = args[0] === undefined ? null : args[0];
          assertJSON(params);
          return invoke("mwb.invokePlugin", {
            plugin: descriptor.name, method: property, params,
            callId: `mwb-${Date.now()}-${++nextCall}`, timeoutMs: descriptor.timeoutMs
          }, descriptor.timeoutMs);
        } catch (error) {
          return Promise.reject(error instanceof MWBBridgeError ? error : new MWBBridgeError(-1102, "Plugin parameters are not valid JSON"));
        }
      });
      return functions.get(property);
    }
  });
}

/** 在根对象只挂载插件命名空间，禁止覆盖 basic 或任何既有根方法。 */
export function attachNativePlugins(target: object, plugins: readonly MWBNativePlugin[]): void {
  for (const descriptor of plugins) {
    if (descriptor[descriptorBrand] !== true || !validName(descriptor.name) || reserved.has(descriptor.name)) throw new Error("Invalid MWB native plugin descriptor");
    if (Object.prototype.hasOwnProperty.call(target, descriptor.name)) throw new Error(`Duplicate MWB plugin: ${descriptor.name}`);
    Object.defineProperty(target, descriptor.name, { value: createNamespace(descriptor), enumerable: true });
  }
}
