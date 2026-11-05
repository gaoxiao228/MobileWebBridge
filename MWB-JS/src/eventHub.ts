import type { DSBridgeLike } from "./bridge";

type Handler = (...args: unknown[]) => unknown;
const hubs = new WeakMap<DSBridgeLike, EventHub>();

/** 同一 bridge 只注册一次原生接收器，避免默认 SDK 和业务组合实例相互覆盖。 */
class EventHub {
  private readonly listeners = new Map<string, Set<Handler>>();
  private back?: { owner: object; handler: () => boolean };

  constructor(private readonly bridge: DSBridgeLike) {
    bridge.register?.("mwb.backBtnPressed", () => this.back?.handler() ?? false);
  }

  on(name: string, handler: Handler): () => void {
    let listeners = this.listeners.get(name);
    if (!listeners) {
      listeners = new Set();
      this.listeners.set(name, listeners);
      this.bridge.register?.(name, (...args: unknown[]) => {
        // 某个业务监听器异常不能中断其他 SDK 实例的事件。
        for (const callback of [...this.listeners.get(name) ?? []]) {
          try { callback(...args); } catch (error) { console.error("MWB event listener failed", error); }
        }
      });
    }
    listeners.add(handler);
    return () => { listeners!.delete(handler); };
  }

  setBack(owner: object, handler?: () => boolean): void {
    if (handler) this.back = { owner, handler };
    else if (this.back?.owner === owner) this.back = undefined;
  }
}

export function getEventHub(bridge: DSBridgeLike): EventHub {
  let hub = hubs.get(bridge);
  if (!hub) { hub = new EventHub(bridge); hubs.set(bridge, hub); }
  return hub;
}
