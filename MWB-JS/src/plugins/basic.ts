import { containerPlugin } from "./container";
import { devicePlugin } from "./device";
import { mediaPlugin } from "./media";
import { storagePlugin } from "./storage";

/** 官方 basic 包含现有原生方法；JS 句柄与事件由 assembleMWB 统一挂载。 */
export const basicPlugin = {
  name: "basic",
  methods: { ...containerPlugin.methods, ...devicePlugin.methods, ...mediaPlugin.methods, ...storagePlugin.methods }
} as const;
