import { afterEach, expect, test, vi } from "vitest";
import { createMWB } from "../src/createMWB";
import { apiMethods } from "../src/apiManifest";

afterEach(() => vi.unstubAllGlobals());

test("redirectTo exposes basic alias and forwards platform options without dropping them", async () => {
  // 捕获新方法漏注册或包装层吞掉 Android 不支持参数的错误。
  const calls: Array<[string, unknown]> = [];
  vi.stubGlobal("window", { _dsbridge: {}, dsBridge: {
    register() {},
    call(method: string, args: unknown, callback?: (value: unknown) => void) {
      calls.push([method, args]);
      callback?.({ errCode: 0 });
    }
  } });
  const sdk = createMWB();
  expect(typeof sdk.redirectTo).toBe("function");
  expect(sdk.basic.redirectTo).toBe(sdk.redirectTo);
  await sdk.basic.redirectTo({ url: "https://example.com/b", title: "B", hidden: false, waitForReady: true });
  expect(calls).toEqual([["mwb.redirectTo", {
    url: "https://example.com/b", title: "B", hidden: false, waitForReady: true
  }]]);
});

test("the default SDK exposes every agreed method", () => {
  vi.stubGlobal("window", { dsBridge: { register() {} } });
  const sdk = createMWB();

  expect(apiMethods.filter(name => typeof sdk[name] !== "function")).toEqual([]);
  // 已移除的水印能力不能继续出现在默认 SDK 对象上。
  expect(sdk).not.toHaveProperty("addWaterMark");
});

test("native calls use the public MWB method and preserve parameter fields", async () => {
  const calls: Array<[string, unknown]> = [];
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      register() {},
      call(method: string, args: unknown, callback?: (value: unknown) => void) {
        calls.push([method, args]);
        callback?.({ errCode: 0 });
      }
    }
  });

  const sdk = createMWB();
  await sdk.navigateTo({ url: "https://example.com", title: "Demo" });
  sdk.setStorageSync("token", "abc", "session", 60);
  sdk.clearStorageSync("session");

  expect(calls).toEqual([
    ["mwb.navigateTo", { url: "https://example.com", title: "Demo" }],
    ["mwb.setStorageSync", { key: "token", data: "abc", groupName: "session", validSecond: 60 }],
    ["mwb.clearStorageSync", { groupName: "session" }]
  ]);
});

test("storage reads return the stored value rather than its transport envelope", () => {
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      register() {},
      call: () => ({ data: { user: 1 } })
    }
  });

  expect(createMWB().getStorageSync<{ user: number }>("profile")).toEqual({ user: 1 });
});

test("navigation text action calls the current JS callback without sending the function to native", async () => {
  // 原生只接收可序列化字段；重复设置时新回调应替换旧回调。
  const handlers = new Map<string, (data: unknown) => void>();
  const sent: unknown[] = [];
  vi.stubGlobal("window", {
    _dsbridge: {},
    dsBridge: {
      register(name: string, handler: (data: unknown) => void) { handlers.set(name, handler); },
      call(method: string, args: unknown, callback?: (value: unknown) => void) {
        if (method === "mwb.setNavigationBarTheme") sent.push(args);
        callback?.({ errCode: 0 });
      }
    }
  });
  const sdk = createMWB();
  const oldClick = vi.fn();
  const newClick = vi.fn();

  await sdk.setNavigationBarTheme({ actionTxt: "保存", actionExt: "draft-42", onActionClick: oldClick });
  handlers.get("mwb.navigationActionClick")?.({ actionExt: "draft-42" });
  await sdk.setNavigationBarTheme({ actionTxt: "完成", onActionClick: newClick });
  handlers.get("mwb.navigationActionClick")?.({ actionExt: "final" });

  expect(sent).toEqual([{ actionTxt: "保存", actionExt: "draft-42" }, { actionTxt: "完成" }]);
  expect(oldClick).toHaveBeenCalledOnce();
  expect(newClick).toHaveBeenCalledWith({ actionExt: "final" });
});
