import { afterEach, expect, test, vi } from "vitest";
import { createMWB } from "../src/createMWB";

afterEach(() => vi.unstubAllGlobals());

test("unsubscribed listeners stay silent after repeated native events", () => {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  vi.stubGlobal("window", {
    dsBridge: {
      register(name: string, handler: (...args: unknown[]) => unknown) {
        handlers.set(name, handler);
      }
    }
  });
  const sdk = createMWB();
  const listener = vi.fn();

  sdk.onPageShow(listener);
  handlers.get("mwb.dispatchEvent")?.({ name: "pageShow" });
  sdk.offPageShow(listener);
  handlers.get("mwb.dispatchEvent")?.({ name: "pageShow" });

  expect(listener).toHaveBeenCalledTimes(1);
});

test("registered JS handlers can be removed without leaving callable behavior", () => {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  vi.stubGlobal("window", {
    dsBridge: {
      register(name: string, handler: (...args: unknown[]) => unknown) {
        handlers.set(name, handler);
      }
    }
  });
  const sdk = createMWB();
  const listener = vi.fn();

  sdk.registerHandler("paymentResult", listener);
  expect(sdk.checkHandlerExist("paymentResult")).toBe(true);
  handlers.get("mwb.paymentResult")?.({ id: 1 });
  sdk.unRegisterHandler("paymentResult", listener);
  handlers.get("mwb.paymentResult")?.({ id: 2 });

  expect(listener).toHaveBeenCalledOnce();
  expect(sdk.checkHandlerExist("paymentResult")).toBe(false);
});

test("the back button returns whether JavaScript consumed it", () => {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  vi.stubGlobal("window", {
    dsBridge: {
      register(name: string, handler: (...args: unknown[]) => unknown) {
        handlers.set(name, handler);
      }
    }
  });
  const sdk = createMWB();

  sdk.onBackBtnPressed(() => true);
  expect(handlers.get("mwb.backBtnPressed")?.()).toBe(true);
  sdk.offBackBtnPressed();
  expect(handlers.get("mwb.backBtnPressed")?.()).toBe(false);
});

test("the back button defaults to native navigation immediately after SDK creation", () => {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  vi.stubGlobal("window", { dsBridge: {
    register(name: string, handler: (...args: unknown[]) => unknown) { handlers.set(name, handler); }
  } });

  createMWB();

  expect(handlers.get("mwb.backBtnPressed")?.()).toBe(false);
});
