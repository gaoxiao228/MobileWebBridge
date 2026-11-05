import type { GenericAsyncResult } from "./types";

/** DSBridge 的最小接口，便于把原生通信限制在一个文件内。 */
export interface DSBridgeLike {
  call(method: string, args?: unknown, callback?: (value: unknown) => void): unknown;
  register?(name: string, handler: (...args: unknown[]) => unknown): void;
  hasNativeMethod?(name: string, type?: string): boolean;
}

type BridgeWindow = Window & {
  _dsbridge?: unknown;
  _dswk?: unknown;
  dsBridge?: DSBridgeLike;
};

/** MWB 传输及原生错误统一使用的异常。 */
export class MWBBridgeError extends Error {
  constructor(public readonly errCode: number, public readonly errorMsg: string) {
    super(errorMsg);
    this.name = "MWBBridgeError";
  }
}

/** 只在调用时读取桥，避免服务端渲染或页面初始化阶段直接访问 window。 */
export function getBridge(): DSBridgeLike {
  if (typeof window === "undefined") {
    throw new MWBBridgeError(-1000, "MWB bridge is not ready");
  }
  const bridgeWindow = window as BridgeWindow;
  const nativeReady = Boolean(bridgeWindow._dsbridge || bridgeWindow._dswk ||
    (typeof navigator !== "undefined" && navigator.userAgent.includes("_dsbridge")));
  if (!nativeReady || !bridgeWindow.dsBridge) {
    throw new MWBBridgeError(-1000, "MWB bridge is not ready");
  }
  return bridgeWindow.dsBridge;
}

/** DSBridge 已经解析普通结果；只对原生额外编码的 JSON 字符串作兼容解析。 */
function parseNative(value: unknown): unknown {
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

export function callSync<T>(method: string, args?: unknown): T {
  const bridge = getBridge();
  if (bridge.hasNativeMethod && !bridge.hasNativeMethod(`mwb.${method}`, "syn")) {
    throw new MWBBridgeError(-1003, `MWB native method is unavailable: ${method}`);
  }
  try {
    const value = parseNative(bridge.call(`mwb.${method}`, args));
    // 同步接口遇到宿主错误时必须抛出，不能把错误对象当作业务返回类型。
    if (value && typeof value === "object" && "errCode" in value &&
        typeof value.errCode === "number" && value.errCode !== 0) {
      throw new MWBBridgeError(value.errCode,
        "errorMsg" in value && typeof value.errorMsg === "string" ? value.errorMsg : `MWB call failed: ${method}`);
    }
    return value as T;
  } catch (error) {
    if (error instanceof MWBBridgeError) throw error;
    throw new MWBBridgeError(-1002, error instanceof Error ? error.message : String(error));
  }
}

export function callAsync<T>(method: string, args?: unknown): Promise<GenericAsyncResult<T>> {
  return new Promise((resolve, reject) => {
    let bridge: DSBridgeLike;
    try {
      bridge = getBridge();
      if (bridge.hasNativeMethod && !bridge.hasNativeMethod(`mwb.${method}`, "asyn")) {
        throw new MWBBridgeError(-1003, `MWB native method is unavailable: ${method}`);
      }
      bridge.call(`mwb.${method}`, args, value => {
        const parsed = parseNative(value);
        if (!parsed || typeof parsed !== "object" || typeof (parsed as GenericAsyncResult<T>).errCode !== "number") {
          reject(new MWBBridgeError(-1001, `Invalid MWB native response: ${method}`));
          return;
        }
        const result = parsed as GenericAsyncResult<T>;
        if (result.errCode === 0) resolve(result);
        else reject(new MWBBridgeError(result.errCode, result.errorMsg ?? `MWB call failed: ${method}`));
      });
    } catch (error) {
      reject(error instanceof MWBBridgeError ? error :
        new MWBBridgeError(-1002, error instanceof Error ? error.message : String(error)));
    }
  });
}
