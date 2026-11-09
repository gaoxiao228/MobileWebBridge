import { afterEach, expect, test, vi } from "vitest";
import * as factory from "../src/createMWB";
import type { GenericAsyncResult } from "../src/types";

interface PaymentMethods {
  pay(params: { orderId: string }): Promise<GenericAsyncResult<{ orderId: string }>>;
}
type PaymentEvents = { finished: { orderId: string } };

/** 只替代真实 WebView 边界；SDK 的组装、校验、Promise 和事件仍实际执行。 */
function nativeHost(invoke?: (args: Record<string, unknown>, done: (value: unknown) => void) => void) {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  const calls: Array<{ method: string; args: Record<string, unknown> }> = [];
  const bridge = {
    register(name: string, handler: (...args: unknown[]) => unknown) { handlers.set(name, handler); },
    hasNativeMethod: () => true,
    call(method: string, value?: unknown, done?: (value: unknown) => void): unknown {
      const args = value as Record<string, unknown>;
      if (method === "mwb.pluginSession") return { errCode: 0, result: { protocol: 1, documentId: "document-a" } };
      if (method === "mwb.pluginInfo") { done?.({ errCode: 0, result: { available: args.plugin === "payment" } }); return; }
      if (method === "mwb.invokePlugin") {
        calls.push({ method, args });
        if (invoke) invoke(args, done!);
        else done?.({ errCode: 0, result: args.params });
        return;
      }
      done?.({ errCode: 0 });
    }
  };
  vi.stubGlobal("window", { _dsbridge: {}, dsBridge: bridge });
  return { handlers, calls, bridge };
}

function payment(timeoutMs = 30000) {
  return factory.defineNativePlugin<PaymentMethods, PaymentEvents>()({ name: "payment", timeoutMs });
}

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

test("basic aliases preserve function identity and synchronous storage", () => {
  nativeHost();
  const sdk = factory.createMWB();
  expect(sdk.basic.navigateTo).toBe(sdk.navigateTo);
  expect(sdk.basic.setStorageSync).toBe(sdk.setStorageSync);
  expect(sdk.basic.onPageShow).toBe(sdk.onPageShow);
  expect(sdk.basic.setStorageSync("key", "value")).toBeUndefined();
});

test("creating another SDK does not erase event listeners or an explicit back handler", () => {
  const { handlers } = nativeHost();
  const first = factory.createMWB();
  const received: unknown[] = [];
  first.onPageShow(value => received.push(value));
  first.onBackBtnPressed(() => true);
  const second = factory.createMWB();
  second.onPageShow(value => received.push(value));
  handlers.get("mwb.dispatchEvent")?.({ name: "pageShow", data: 42 });
  expect(received).toEqual([42, 42]);
  expect(handlers.get("mwb.backBtnPressed")?.()).toBe(true);
  second.offBackBtnPressed();
  expect(handlers.get("mwb.backBtnPressed")?.()).toBe(true);
});

test("native descriptors require no method list and route the accessed method", async () => {
  const { calls } = nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  await expect(sdk.payment.pay({ orderId: "ORDER_1" })).resolves.toEqual({ errCode: 0, result: { orderId: "ORDER_1" } });
  expect(calls[0].args).toMatchObject({ protocol: 1, documentId: "document-a", plugin: "payment", method: "pay", params: { orderId: "ORDER_1" }, timeoutMs: 30000 });
  expect(typeof calls[0].args.callId).toBe("string");
  expect(sdk.payment.pay).toBe(sdk.payment.pay);
  expect(sdk.basic.navigateTo).toBe(sdk.navigateTo);
});

test("hasPlugin checks native installation rather than the JS description", async () => {
  nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  await expect(sdk.hasPlugin("payment")).resolves.toBe(true);
  await expect(sdk.hasPlugin("network")).resolves.toBe(false);
});

test("missing and unsupported native methods reject with their original code", async () => {
  for (const errCode of [-1100, -1101, 2001]) {
    nativeHost((_args, done) => done({ errCode, errorMsg: "unavailable" }));
    const sdk = factory.createMWB({ plugins: [payment()] });
    await expect(sdk.payment.pay({ orderId: "1" })).rejects.toMatchObject({ errCode, errorMsg: "unavailable" });
  }
});

test("proxy inspection never creates business calls or turns a plugin into a promise", async () => {
  const { calls } = nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  await expect(Promise.resolve(sdk.payment)).resolves.toBe(sdk.payment);
  expect(JSON.stringify(sdk.payment)).toBe("{}");
  expect(Reflect.get(sdk.payment, Symbol.iterator)).toBeUndefined();
  expect(Reflect.get(sdk.payment, "constructor")).toBeUndefined();
  expect(Reflect.get(sdk.payment, "catch")).toBeUndefined();
  expect(calls).toEqual([]);
});

test("non JSON parameters reject before crossing the bridge", async () => {
  const { calls } = nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  const cyclic: Record<string, unknown> = {}; cyclic.self = cyclic;
  for (const value of [cyclic, { n: NaN }, { f() {} }, new Date(), { n: BigInt(1) }, { a: undefined }]) {
    await expect(sdk.payment.pay(value as { orderId: string })).rejects.toMatchObject({ errCode: -1102 });
  }
  expect(calls).toEqual([]);
});

test("accessor parameters cannot change between validation and bridge serialization", async () => {
  const { calls } = nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  let reads = 0;
  const params = Object.defineProperty({}, "orderId", { enumerable: true, get() { reads++; return "1"; } });
  await expect(sdk.payment.pay(params as { orderId: string })).rejects.toMatchObject({ errCode: -1102 });
  expect(reads).toBe(0);
  expect(calls).toEqual([]);
});

test("native callbacks complete once and preserve an explicit null result", async () => {
  nativeHost((_args, done) => { done({ errCode: 0, result: null }); done({ errCode: 9 }); });
  const sdk = factory.createMWB({ plugins: [payment()] });
  await expect(sdk.payment.pay({ orderId: "1" })).resolves.toEqual({ errCode: 0, result: null });
});

test("a missing callback times out instead of leaving a payment promise pending", async () => {
  vi.useFakeTimers();
  nativeHost(() => {});
  const sdk = factory.createMWB({ plugins: [payment(50)] });
  const rejection = expect(sdk.payment.pay({ orderId: "1" })).rejects.toMatchObject({ errCode: -1103 });
  await vi.advanceTimersByTimeAsync(50);
  await rejection;
});

test("old shells report protocol unavailability without affecting basic APIs", async () => {
  const { bridge } = nativeHost();
  bridge.hasNativeMethod = () => false;
  const sdk = factory.createMWB({ plugins: [payment()] });
  await expect(sdk.payment.pay({ orderId: "1" })).rejects.toMatchObject({ errCode: -1106 });
});

test("plugin events are scoped to a document and unsubscribe stops delivery", async () => {
  const { handlers } = nativeHost();
  const sdk = factory.createMWB({ plugins: [payment()] });
  const values: unknown[] = [];
  const stop = sdk.payment.on("finished", value => values.push(value));
  handlers.get("mwb.pluginEvent")?.({ documentId: "old", plugin: "payment", name: "finished", data: { orderId: "old" } });
  handlers.get("mwb.pluginEvent")?.({ documentId: "document-a", plugin: "payment", name: "finished", data: { orderId: "1" } });
  stop();
  handlers.get("mwb.pluginEvent")?.({ documentId: "document-a", plugin: "payment", name: "finished", data: { orderId: "2" } });
  expect(values).toEqual([{ orderId: "1" }]);
});

test("plugin conflicts and invalid configuration fail during composition", () => {
  nativeHost();
  expect(() => factory.createMWB({ plugins: [payment(), payment()] })).toThrow(/duplicate/i);
  for (const name of ["basic", "navigateTo", "redirectTo", "version", "on", "dispatchEvent", "backBtnPressed", "pluginSession", "__proto__", "bad-name"]) {
    expect(() => factory.defineNativePlugin<PaymentMethods>()({ name })).toThrow();
  }
  // 旧数组组合也不能覆盖 Core 或事件入口。
  for (const name of ["basic", "version", "hasPlugin", "registerHandler", "__proto__"]) {
    expect(() => factory.createMWB([{ name: "legacy", methods: { [name]: () => undefined } }])).toThrow();
  }
  expect(() => payment(0)).toThrow();
  expect(() => payment(120001)).toThrow();
});

// 编译契约：类型错误不能被动态 Proxy 的运行时能力掩盖。
function typeContract() {
  const network = factory.defineNativePlugin<{ request(p: { url: string }): Promise<GenericAsyncResult<string>> }>()({ name: "network" });
  const sdk = factory.createMWB({ plugins: [payment(), network] });
  sdk.payment.pay({ orderId: "1" });
  sdk.network.request({ url: "/profile" });
  // @ts-expect-error 支付参数必须有 orderId。
  sdk.payment.pay({ url: "/profile" });
  // @ts-expect-error 未声明的方法不可通过类型检查。
  sdk.payment.refund();
  // @ts-expect-error 事件载荷必须符合声明。
  sdk.payment.on("finished", (value: { wrong: number }) => value);
  // @ts-expect-error then 为 Proxy 的保留探测属性，不能声明为业务方法。
  factory.defineNativePlugin<{ then(p: null): Promise<GenericAsyncResult<string>> }>()({ name: "bad" });
}
void typeContract;
