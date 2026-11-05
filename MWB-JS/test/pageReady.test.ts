import { afterEach, expect, test, vi } from "vitest";
import { createMWB, defineNativePlugin } from "../src/createMWB";

/** 仅替代桥边界，通知组装、身份获取、错误与超时运行真实 SDK。 */
function host(options: { errCode?: number; supported?: boolean; silent?: boolean } = {}) {
  const calls: Array<{ method: string; args: unknown }> = [];
  const bridge = {
    register() {},
    hasNativeMethod: () => options.supported !== false,
    call(method: string, args?: unknown, callback?: (value: unknown) => void) {
      calls.push({ method, args });
      if (method === "mwb.pluginSession") {
        return { errCode: 0, result: { protocol: 1, documentId: "page-a" } };
      }
      if (!options.silent) callback?.({ errCode: options.errCode ?? 0 });
    }
  };
  vi.stubGlobal("window", { _dsbridge: {}, dsBridge: bridge });
  return calls;
}

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

test("page readiness uses the document-bound builtin gateway and preserves aliases", async () => {
  const calls = host();
  const sdk = createMWB();
  expect(sdk.basic.notifyPageReady).toBe(sdk.notifyPageReady);
  await expect(sdk.basic.notifyPageReady()).resolves.toEqual({ errCode: 0 });
  expect(calls).toHaveLength(2);
  expect(calls[1]).toMatchObject({ method: "mwb.invokePlugin", args: {
    protocol: 1, documentId: "page-a", plugin: "basic", method: "notifyPageReady", params: null
  } });
});

test("unsupported native versions, stale documents and browsers never report readiness success", async () => {
  host({ supported: false });
  await expect(createMWB().basic.notifyPageReady()).rejects.toMatchObject({ errCode: -1106 });
  for (const errCode of [-1101, -1104, -1006]) {
    host({ errCode });
    await expect(createMWB().basic.notifyPageReady()).rejects.toMatchObject({ errCode });
  }
  vi.stubGlobal("window", {});
  await expect(createMWB().basic.notifyPageReady()).rejects.toMatchObject({ errCode: -1000 });
});

test("readiness has a bounded wait when navigation discards its native reply", async () => {
  vi.useFakeTimers();
  host({ silent: true });
  const result = expect(createMWB().basic.notifyPageReady()).rejects.toMatchObject({ errCode: -1103 });
  await vi.advanceTimersByTimeAsync(30000);
  await result;
  expect(vi.getTimerCount()).toBe(0);
});

test("the readiness method cannot be shadowed by a native plugin", () => {
  expect(() => defineNativePlugin()({ name: "notifyPageReady" })).toThrow(/reserved/i);
});
