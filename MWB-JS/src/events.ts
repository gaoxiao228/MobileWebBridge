import type { GenericCallbackFunc, MWBJSSDK } from "./types";
import type { DSBridgeLike } from "./bridge";
import { getEventHub } from "./eventHub";

type EventName = "networkStatusChange" | "appShow" | "appHide" |
  "remoteNotificationReceive" | "pageShow" | "pageHide";

/** DSBridge 只保留一个注册函数；多监听器和解绑由这一层管理。 */
export function createEvents(): Pick<MWBJSSDK,
  "registerHandler" | "unRegisterHandlers" | "unRegisterHandler" |
  "checkHandlerExist" | "onNetworkStatusChange" | "offNetworkStatusChange" |
  "onAppShow" | "offAppShow" | "onAppHide" | "offAppHide" |
  "onRemoteNotificationReceive" | "offRemoteNotificationReceive" |
  "onPageShow" | "offPageShow" | "onPageHide" | "offPageHide" |
  "onBackBtnPressed" | "offBackBtnPressed"> {
  const custom = new Map<string, Set<GenericCallbackFunc>>();
  const listeners = new Map<EventName, Set<GenericCallbackFunc>>();
  let backHandler: (() => boolean) | undefined;
  let eventBridge: DSBridgeLike | undefined;
  const owner = {};
  const relayStops = new Map<string, () => void>();

  function bridge(): DSBridgeLike | undefined {
    if (typeof window === "undefined") return undefined;
    return (window as Window & { dsBridge?: DSBridgeLike }).dsBridge;
  }

  function ensureEventsRegistered(): void {
    const current = bridge();
    if (!current?.register || eventBridge === current) return;
    relayStops.forEach(stop => stop());
    relayStops.clear();
    if (eventBridge) getEventHub(eventBridge).setBack(owner);
    const hub = getEventHub(current);
    relayStops.set("dispatchEvent", hub.on("mwb.dispatchEvent", (message: unknown) => {
      if (!message || typeof message !== "object") return;
      const event = message as { name?: EventName; data?: unknown };
      if (!event.name) return;
      for (const handler of [...listeners.get(event.name) ?? []]) {
        try { handler(event.data); } catch (error) { console.error("MWB event listener failed", error); }
      }
    }));
    eventBridge = current;
    if (backHandler) hub.setBack(owner, backHandler);
    for (const name of custom.keys()) attachCustom(name);
  }

  function attachCustom(name: string): void {
    if (!eventBridge || relayStops.has(`custom:${name}`)) return;
    relayStops.set(`custom:${name}`, getEventHub(eventBridge).on(`mwb.${name}`, (data: unknown) => {
      for (const callback of [...custom.get(name) ?? []]) {
        try { callback(data); } catch (error) { console.error("MWB handler failed", error); }
      }
    }));
  }

  function on(name: EventName, handler: GenericCallbackFunc): void {
    ensureEventsRegistered();
    if (!listeners.has(name)) listeners.set(name, new Set());
    listeners.get(name)?.add(handler);
  }

  function off(name: EventName, handler: GenericCallbackFunc): void {
    listeners.get(name)?.delete(handler);
  }

  // 容器返回键即使没有业务订阅也必须得到 false，避免原生导航等待不存在的句柄。
  ensureEventsRegistered();

  return {
    registerHandler(handlerName, handler) {
      ensureEventsRegistered();
      if (!custom.has(handlerName)) {
        custom.set(handlerName, new Set());
      }
      custom.get(handlerName)?.add(handler);
      attachCustom(handlerName);
    },
    unRegisterHandlers(handlerName) { custom.delete(handlerName); },
    unRegisterHandler(handlerName, handler) {
      const handlers = custom.get(handlerName);
      handlers?.delete(handler);
      if (handlers?.size === 0) custom.delete(handlerName);
    },
    checkHandlerExist(handlerName) { return Boolean(custom.get(handlerName)?.size); },
    onNetworkStatusChange(handler) { on("networkStatusChange", handler); },
    offNetworkStatusChange(handler) { off("networkStatusChange", handler); },
    onAppShow(handler) { on("appShow", handler); },
    offAppShow(handler) { off("appShow", handler); },
    onAppHide(handler) { on("appHide", handler); },
    offAppHide(handler) { off("appHide", handler); },
    onRemoteNotificationReceive(handler) { on("remoteNotificationReceive", handler); },
    offRemoteNotificationReceive(handler) { off("remoteNotificationReceive", handler); },
    onPageShow(handler) { on("pageShow", handler); },
    offPageShow(handler) { off("pageShow", handler); },
    onPageHide(handler) { on("pageHide", handler); },
    offPageHide(handler) { off("pageHide", handler); },
    onBackBtnPressed(handler) {
      ensureEventsRegistered(); backHandler = handler;
      if (eventBridge) getEventHub(eventBridge).setBack(owner, handler);
    },
    offBackBtnPressed() {
      backHandler = undefined;
      if (eventBridge) getEventHub(eventBridge).setBack(owner);
    }
  };
}
