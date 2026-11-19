import { containerPlugin } from "./container.js";
import { devicePlugin } from "./device.js";
import { mediaPlugin } from "./media.js";
import { storagePlugin } from "./storage.js";

/** 官方 basic 包含现有原生方法；JS 句柄与事件由 assembleMWB 统一挂载。 */
export const basicPlugin = {
  name: "basic",
  methods: { ...containerPlugin.methods, ...devicePlugin.methods, ...mediaPlugin.methods, ...storagePlugin.methods }
} as const;
