import { callSync } from "../bridge";
import type { MWBJSSDK, ReturnStorageResult } from "../types";

/** 按可选分组名隔离的同步存储能力。 */
export const storagePlugin = {
  name: "storage",
  methods: {
    setStorageSync(key, data, groupName, validSecond) {
      callSync("setStorageSync", { key, data, groupName, validSecond });
    },
    getStorageSync<T>(key: string, groupName?: string): T | undefined {
      const response = callSync<ReturnStorageResult | undefined>("getStorageSync", { key, groupName });
      return response?.data as T | undefined;
    },
    removeStorageSync(key, groupName) {
      callSync("removeStorageSync", { key, groupName });
    },
    clearStorageSync(groupName) {
      callSync("clearStorageSync", { groupName });
    }
  } satisfies Pick<MWBJSSDK,
    "setStorageSync" | "getStorageSync" | "removeStorageSync" | "clearStorageSync">
} as const;
