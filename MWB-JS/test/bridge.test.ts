import { afterEach, expect, test, vi } from "vitest";
import { callAsync, callSync } from "../src/bridge";

afterEach(() => vi.unstubAllGlobals());

test("synchronous calls use the MWB namespace and preserve the result", () => {
  const calls: unknown[][] = [];
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      call(method: string, args: unknown) {
        calls.push([method, args]);
        return { appId: "demo" };
      }
    }
  });

  expect(callSync<{ appId: string }>("getAppInfoSync")).toEqual({ appId: "demo" });
  expect(calls).toEqual([["mwb.getAppInfoSync", undefined]]);
});

test("asynchronous calls pass one argument object and return the native result", async () => {
  const calls: unknown[][] = [];
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      call(method: string, args: unknown, callback: (value: unknown) => void) {
        calls.push([method, args]);
        callback({ errCode: 0, result: { code: "123" } });
      }
    }
  });

  await expect(callAsync("scanCode", { scanType: ["qrCode"] })).resolves.toEqual({
    errCode: 0,
    result: { code: "123" }
  });
  expect(calls).toEqual([["mwb.scanCode", { scanType: ["qrCode"] }]]);
});

test("missing native bridge gives a diagnostic error", async () => {
  vi.stubGlobal("window", {});

  expect(() => callSync("getAppInfoSync")).toThrowError(/bridge is not ready/i);
  await expect(callAsync("scanCode")).rejects.toMatchObject({ errCode: -1000 });
});

test("a synchronous plain string remains a string", () => {
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: { call: () => "plain text" }
  });

  expect(callSync("getClipboardDataSync")).toBe("plain text");
});

test("native failures reject with the same error code", async () => {
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      call(_method: string, _args: unknown, callback: (value: unknown) => void) {
        callback({ errCode: 12, errorMsg: "permission denied" });
      }
    }
  });

  await expect(callAsync("scanCode")).rejects.toMatchObject({
    errCode: 12,
    errorMsg: "permission denied"
  });
});

test("synchronous host errors throw instead of masquerading as app data", () => {
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: { call: () => ({ errCode: -1005, errorMsg: "App info is not configured" }) }
  });

  expect(() => callSync("getAppInfoSync")).toThrowError(/App info is not configured/);
});
