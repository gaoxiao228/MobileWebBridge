import { createMWB, defineNativePlugin, type GenericAsyncResult } from "../../MWB-JS/src/index";

interface NetworkMethods {
  /** 请求由两个 Sample 的宿主网络层执行，JS 不使用 fetch 模拟。 */
  request(params: { url: string; method: "GET" | "POST"; headers?: Record<string, string>; body?: string }):
    Promise<GenericAsyncResult<{ status: number; headers: Record<string, string>; body: string }>>;
}
type NetworkEvents = { requestFinished: { url: string; status: number } };

const networkPlugin = defineNativePlugin<NetworkMethods, NetworkEvents>()({ name: "network", timeoutMs: 30000 });

// 自定义入口由接入方构建；名称、方法参数和事件均获得静态类型，无 methods 清单。
window.mwb = createMWB({ plugins: [networkPlugin] });
