/*!
MIT License

Copyright (c) 2026 gaoxiao228

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# DSBridge third-party notice

DSBridge JavaScript 3.1.4: https://www.npmjs.com/package/dsbridge/v/3.1.4
DSBridge Android 3.0.0: https://github.com/wendux/DSBridge-Android/tree/d3e5ebc6ca8170f97e420f2f482680c8e149b471
DSBridge iOS 3.0.6: https://github.com/wendux/DSBridge-IOS/tree/f0e3c724dd362800528f8b6c788bdad7006cc187

Author: wendux (杜文 / Du Wen), as identified by upstream package metadata and source.
The upstream npm metadata, Android readme.md and iOS podspec declare MIT.
The pinned native trees do not provide a separate LICENSE file; the MIT terms
are reproduced below without inventing an absent upstream copyright notice.
Original iOS source notices are retained verbatim:

Copyright © 2016年 杜文. All rights reserved.
Copyright © 2018年 杜文. All rights reserved.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
"use strict";
(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // node_modules/dsbridge/index.js
  var require_dsbridge = __commonJS({
    "node_modules/dsbridge/index.js"(exports, module) {
      var bridge = {
        default: exports,
        // for typescript
        call: function(method, args, cb) {
          var ret = "";
          if (typeof args == "function") {
            cb = args;
            args = {};
          }
          var arg = { data: args === void 0 ? null : args };
          if (typeof cb == "function") {
            var cbName = "dscb" + window.dscb++;
            window[cbName] = cb;
            arg["_dscbstub"] = cbName;
          }
          arg = JSON.stringify(arg);
          if (window._dsbridge) {
            ret = _dsbridge.call(method, arg);
          } else if (window._dswk || navigator.userAgent.indexOf("_dsbridge") != -1) {
            ret = prompt("_dsbridge=" + method, arg);
          }
          return JSON.parse(ret || "{}").data;
        },
        register: function(name, fun, asyn) {
          var q = asyn ? window._dsaf : window._dsf;
          if (!window._dsInit) {
            window._dsInit = true;
            setTimeout(function() {
              bridge.call("_dsb.dsinit");
            }, 0);
          }
          if (typeof fun == "object") {
            q._obs[name] = fun;
          } else {
            q[name] = fun;
          }
        },
        registerAsyn: function(name, fun) {
          this.register(name, fun, true);
        },
        hasNativeMethod: function(name, type) {
          return this.call("_dsb.hasNativeMethod", { name, type: type || "all" });
        },
        disableJavascriptDialogBlock: function(disable) {
          this.call("_dsb.disableJavascriptDialogBlock", {
            disable: disable !== false
          });
        }
      };
      !(function() {
        if (window._dsf) return;
        var ob = {
          _dsf: {
            _obs: {}
          },
          _dsaf: {
            _obs: {}
          },
          dscb: 0,
          dsBridge: bridge,
          close: function() {
            bridge.call("_dsb.closePage");
          },
          _handleMessageFromNative: function(info) {
            var arg = JSON.parse(info.data);
            var ret = {
              id: info.callbackId,
              complete: true
            };
            var f = this._dsf[info.method];
            var af = this._dsaf[info.method];
            var callSyn = function(f2, ob3) {
              ret.data = f2.apply(ob3, arg);
              bridge.call("_dsb.returnValue", ret);
            };
            var callAsyn = function(f2, ob3) {
              arg.push(function(data, complete) {
                ret.data = data;
                ret.complete = complete !== false;
                bridge.call("_dsb.returnValue", ret);
              });
              f2.apply(ob3, arg);
            };
            if (f) {
              callSyn(f, this._dsf);
            } else if (af) {
              callAsyn(af, this._dsaf);
            } else {
              var name = info.method.split(".");
              if (name.length < 2) return;
              var method = name.pop();
              var namespace = name.join(".");
              var obs = this._dsf._obs;
              var ob2 = obs[namespace] || {};
              var m = ob2[method];
              if (m && typeof m == "function") {
                callSyn(m, ob2);
                return;
              }
              obs = this._dsaf._obs;
              ob2 = obs[namespace] || {};
              m = ob2[method];
              if (m && typeof m == "function") {
                callAsyn(m, ob2);
                return;
              }
            }
          }
        };
        for (var attr in ob) {
          window[attr] = ob[attr];
        }
        bridge.register("_hasJavascriptMethod", function(method, tag) {
          var name = method.split(".");
          if (name.length < 2) {
            return !!(_dsf[name] || _dsaf[name]);
          } else {
            var method = name.pop();
            var namespace = name.join(".");
            var ob2 = _dsf._obs[namespace] || _dsaf._obs[namespace];
            return ob2 && !!ob2[method];
          }
        });
      })();
      module.exports = bridge;
    }
  });

  // src/index.ts
  var import_dsbridge = __toESM(require_dsbridge(), 1);

  // src/types.ts
  var version = "0.1.4";

  // src/eventHub.ts
  var hubs = /* @__PURE__ */ new WeakMap();
  var EventHub = class {
    constructor(bridge) {
      this.bridge = bridge;
      this.listeners = /* @__PURE__ */ new Map();
      bridge.register?.("mwb.backBtnPressed", () => this.back?.handler() ?? false);
    }
    on(name, handler) {
      let listeners = this.listeners.get(name);
      if (!listeners) {
        listeners = /* @__PURE__ */ new Set();
        this.listeners.set(name, listeners);
        this.bridge.register?.(name, (...args) => {
          for (const callback of [...this.listeners.get(name) ?? []]) {
            try {
              callback(...args);
            } catch (error) {
              console.error("MWB event listener failed", error);
            }
          }
        });
      }
      listeners.add(handler);
      return () => {
        listeners.delete(handler);
      };
    }
    setBack(owner, handler) {
      if (handler) this.back = { owner, handler };
      else if (this.back?.owner === owner) this.back = void 0;
    }
  };
  function getEventHub(bridge) {
    let hub = hubs.get(bridge);
    if (!hub) {
      hub = new EventHub(bridge);
      hubs.set(bridge, hub);
    }
    return hub;
  }

  // src/events.ts
  function createEvents() {
    const custom = /* @__PURE__ */ new Map();
    const listeners = /* @__PURE__ */ new Map();
    let backHandler;
    let eventBridge;
    const owner = {};
    const relayStops = /* @__PURE__ */ new Map();
    function bridge() {
      if (typeof window === "undefined") return void 0;
      return window.dsBridge;
    }
    function ensureEventsRegistered() {
      const current = bridge();
      if (!current?.register || eventBridge === current) return;
      relayStops.forEach((stop) => stop());
      relayStops.clear();
      if (eventBridge) getEventHub(eventBridge).setBack(owner);
      const hub = getEventHub(current);
      relayStops.set("dispatchEvent", hub.on("mwb.dispatchEvent", (message) => {
        if (!message || typeof message !== "object") return;
        const event = message;
        if (!event.name) return;
        for (const handler of [...listeners.get(event.name) ?? []]) {
          try {
            handler(event.data);
          } catch (error) {
            console.error("MWB event listener failed", error);
          }
        }
      }));
      eventBridge = current;
      if (backHandler) hub.setBack(owner, backHandler);
      for (const name of custom.keys()) attachCustom(name);
    }
    function attachCustom(name) {
      if (!eventBridge || relayStops.has(`custom:${name}`)) return;
      relayStops.set(`custom:${name}`, getEventHub(eventBridge).on(`mwb.${name}`, (data) => {
        for (const callback of [...custom.get(name) ?? []]) {
          try {
            callback(data);
          } catch (error) {
            console.error("MWB handler failed", error);
          }
        }
      }));
    }
    function on(name, handler) {
      ensureEventsRegistered();
      if (!listeners.has(name)) listeners.set(name, /* @__PURE__ */ new Set());
      listeners.get(name)?.add(handler);
    }
    function off(name, handler) {
      listeners.get(name)?.delete(handler);
    }
    ensureEventsRegistered();
    return {
      registerHandler(handlerName, handler) {
        ensureEventsRegistered();
        if (!custom.has(handlerName)) {
          custom.set(handlerName, /* @__PURE__ */ new Set());
        }
        custom.get(handlerName)?.add(handler);
        attachCustom(handlerName);
      },
      unRegisterHandlers(handlerName) {
        custom.delete(handlerName);
      },
      unRegisterHandler(handlerName, handler) {
        const handlers = custom.get(handlerName);
        handlers?.delete(handler);
        if (handlers?.size === 0) custom.delete(handlerName);
      },
      checkHandlerExist(handlerName) {
        return Boolean(custom.get(handlerName)?.size);
      },
      onNetworkStatusChange(handler) {
        on("networkStatusChange", handler);
      },
      offNetworkStatusChange(handler) {
        off("networkStatusChange", handler);
      },
      onAppShow(handler) {
        on("appShow", handler);
      },
      offAppShow(handler) {
        off("appShow", handler);
      },
      onAppHide(handler) {
        on("appHide", handler);
      },
      offAppHide(handler) {
        off("appHide", handler);
      },
      onRemoteNotificationReceive(handler) {
        on("remoteNotificationReceive", handler);
      },
      offRemoteNotificationReceive(handler) {
        off("remoteNotificationReceive", handler);
      },
      onPageShow(handler) {
        on("pageShow", handler);
      },
      offPageShow(handler) {
        off("pageShow", handler);
      },
      onPageHide(handler) {
        on("pageHide", handler);
      },
      offPageHide(handler) {
        off("pageHide", handler);
      },
      onBackBtnPressed(handler) {
        ensureEventsRegistered();
        backHandler = handler;
        if (eventBridge) getEventHub(eventBridge).setBack(owner, handler);
      },
      offBackBtnPressed() {
        backHandler = void 0;
        if (eventBridge) getEventHub(eventBridge).setBack(owner);
      }
    };
  }

  // src/assembleMWB.ts
  function assembleMWB(plugins) {
    const events = createEvents();
    const protectedNames = /* @__PURE__ */ new Set(["basic", "version", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin", "pluginEvent", "constructor", "prototype", "__proto__", ...Object.keys(events)]);
    const methods = /* @__PURE__ */ Object.create(null);
    const selected = /* @__PURE__ */ new Set();
    for (const plugin of plugins) {
      if (selected.has(plugin)) continue;
      selected.add(plugin);
      for (const [name, method] of Object.entries(plugin.methods)) {
        if (protectedNames.has(name)) throw new Error(`Reserved MWB basic method: ${name}`);
        if (Object.prototype.hasOwnProperty.call(methods, name)) throw new Error(`Duplicate MWB basic method: ${name}`);
        methods[name] = method;
      }
    }
    const nativeSetTheme = methods.setNavigationBarTheme;
    if (nativeSetTheme) {
      let currentActionClick;
      methods.setNavigationBarTheme = async (param) => {
        const { onActionClick, ...nativeParam } = param;
        const result = await nativeSetTheme(nativeParam);
        if (currentActionClick) events.unRegisterHandler("navigationActionClick", currentActionClick);
        currentActionClick = void 0;
        if (nativeParam.actionTxt?.trim() && onActionClick) {
          events.registerHandler("navigationActionClick", onActionClick);
          currentActionClick = onActionClick;
        }
        return result;
      };
    }
    const basic = Object.freeze({ ...methods, ...events });
    return { version, ...basic, basic };
  }

  // src/apiManifest.ts
  var apiMethods = [
    "notifyPageReady",
    "setEnableDebug",
    "openAppAuthorizeSetting",
    "toast",
    "getAppInfoSync",
    "setBadgeCount",
    "navigateTo",
    "redirectTo",
    "navigateBack",
    "navigateBackToRoot",
    "openExternalBrowser",
    "setNavigationBarTheme",
    "getDeviceInfoSync",
    "getClipboardDataSync",
    "setClipboardData",
    "makePhoneCall",
    "getNetworkTypeSync",
    "getNotificationSwitchStatus",
    "cleanWebviewCache",
    "compressImage",
    "scanCode",
    "saveImageToPhotosAlbum",
    "chooseImage",
    "setStorageSync",
    "getStorageSync",
    "removeStorageSync",
    "clearStorageSync",
    "openFile",
    "exitApp",
    "checkRequestCameraPermissions",
    "convertImagePathToBase64",
    "openNativePage",
    "registerHandler",
    "unRegisterHandlers",
    "unRegisterHandler",
    "checkHandlerExist",
    "onNetworkStatusChange",
    "offNetworkStatusChange",
    "onAppShow",
    "offAppShow",
    "onAppHide",
    "offAppHide",
    "onRemoteNotificationReceive",
    "offRemoteNotificationReceive",
    "onPageShow",
    "offPageShow",
    "onPageHide",
    "offPageHide",
    "onBackBtnPressed",
    "offBackBtnPressed"
  ];

  // src/bridge.ts
  var MWBBridgeError = class extends Error {
    constructor(errCode, errorMsg) {
      super(errorMsg);
      this.errCode = errCode;
      this.errorMsg = errorMsg;
      this.name = "MWBBridgeError";
    }
  };
  function getBridge() {
    if (typeof window === "undefined") {
      throw new MWBBridgeError(-1e3, "MWB bridge is not ready");
    }
    const bridgeWindow = window;
    const nativeReady = Boolean(bridgeWindow._dsbridge || bridgeWindow._dswk || typeof navigator !== "undefined" && navigator.userAgent.includes("_dsbridge"));
    if (!nativeReady || !bridgeWindow.dsBridge) {
      throw new MWBBridgeError(-1e3, "MWB bridge is not ready");
    }
    return bridgeWindow.dsBridge;
  }
  function parseNative(value) {
    if (typeof value !== "string") return value;
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }
  function callSync(method, args) {
    const bridge = getBridge();
    if (bridge.hasNativeMethod && !bridge.hasNativeMethod(`mwb.${method}`, "syn")) {
      throw new MWBBridgeError(-1003, `MWB native method is unavailable: ${method}`);
    }
    try {
      const value = parseNative(bridge.call(`mwb.${method}`, args));
      if (value && typeof value === "object" && "errCode" in value && typeof value.errCode === "number" && value.errCode !== 0) {
        throw new MWBBridgeError(
          value.errCode,
          "errorMsg" in value && typeof value.errorMsg === "string" ? value.errorMsg : `MWB call failed: ${method}`
        );
      }
      return value;
    } catch (error) {
      if (error instanceof MWBBridgeError) throw error;
      throw new MWBBridgeError(-1002, error instanceof Error ? error.message : String(error));
    }
  }
  function callAsync(method, args) {
    return new Promise((resolve, reject) => {
      let bridge;
      try {
        bridge = getBridge();
        if (bridge.hasNativeMethod && !bridge.hasNativeMethod(`mwb.${method}`, "asyn")) {
          throw new MWBBridgeError(-1003, `MWB native method is unavailable: ${method}`);
        }
        bridge.call(`mwb.${method}`, args, (value) => {
          const parsed = parseNative(value);
          if (!parsed || typeof parsed !== "object" || typeof parsed.errCode !== "number") {
            reject(new MWBBridgeError(-1001, `Invalid MWB native response: ${method}`));
            return;
          }
          const result = parsed;
          if (result.errCode === 0) resolve(result);
          else reject(new MWBBridgeError(result.errCode, result.errorMsg ?? `MWB call failed: ${method}`));
        });
      } catch (error) {
        reject(error instanceof MWBBridgeError ? error : new MWBBridgeError(-1002, error instanceof Error ? error.message : String(error)));
      }
    });
  }

  // src/nativePlugins.ts
  var descriptorBrand = /* @__PURE__ */ Symbol("MWBNativePlugin");
  var reserved = /* @__PURE__ */ new Set([...apiMethods, "basic", "version", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin", "pluginEvent", "dispatchEvent", "backBtnPressed", "on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__"]);
  var methodReserved = /* @__PURE__ */ new Set(["on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__"]);
  function validName(name) {
    return typeof name === "string" && /^[a-z][a-zA-Z0-9_]*$/.test(name);
  }
  function assertJSON(value, ancestors = /* @__PURE__ */ new Set()) {
    if (value === null || typeof value === "string" || typeof value === "boolean") return;
    if (typeof value === "number" && Number.isFinite(value)) return;
    if (typeof value !== "object" || value === null || ancestors.has(value)) throw new MWBBridgeError(-1102, "Plugin data must be finite, acyclic JSON");
    const prototype = Object.getPrototypeOf(value);
    if (!Array.isArray(value) && prototype !== Object.prototype && prototype !== null) throw new MWBBridgeError(-1102, "Plugin data must contain plain JSON objects");
    if (Object.getOwnPropertySymbols(value).length) throw new MWBBridgeError(-1102, "Symbol properties are not JSON data");
    if (Object.values(Object.getOwnPropertyDescriptors(value)).some((property) => property.get || property.set)) {
      throw new MWBBridgeError(-1102, "Plugin data must not contain accessors");
    }
    ancestors.add(value);
    const values = Array.isArray(value) ? Array.from(value) : Object.values(value);
    for (const child of values) assertJSON(child, ancestors);
    ancestors.delete(value);
  }
  function envelope(value) {
    if (typeof value === "string") {
      try {
        value = JSON.parse(value);
      } catch {
        throw new MWBBridgeError(-1102, "Invalid plugin response JSON");
      }
    }
    if (!value || typeof value !== "object" || !("errCode" in value) || !Number.isInteger(value.errCode)) throw new MWBBridgeError(-1102, "Invalid plugin response");
    const response = value;
    if (response.errCode !== 0) throw new MWBBridgeError(response.errCode, response.errorMsg ?? "MWB plugin call failed");
    if ("result" in response) assertJSON(response.result);
    return response;
  }
  function session(bridge) {
    if (bridge.hasNativeMethod && !bridge.hasNativeMethod("mwb.pluginSession", "syn")) throw new MWBBridgeError(-1106, "This app does not support MWB native plugins");
    let value;
    try {
      value = bridge.call("mwb.pluginSession");
    } catch (error) {
      throw new MWBBridgeError(-1106, error instanceof Error ? error.message : "Plugin session unavailable");
    }
    if (value === void 0 || value === null || value === "") throw new MWBBridgeError(-1106, "This app does not support MWB native plugins");
    const info = envelope(value).result;
    if (info?.protocol !== 1 || typeof info.documentId !== "string" || !info.documentId) throw new MWBBridgeError(-1106, "Incompatible MWB plugin protocol");
    return info;
  }
  var nextCall = 0;
  function invoke(gateway, payload, timeoutMs) {
    return new Promise((resolve, reject) => {
      let timer;
      let finished = false;
      const complete = (value, error) => {
        if (finished) return;
        finished = true;
        if (timer !== void 0) clearTimeout(timer);
        try {
          if (error) throw error;
          resolve(envelope(value));
        } catch (failure) {
          reject(failure instanceof MWBBridgeError ? failure : new MWBBridgeError(-1105, failure instanceof Error ? failure.message : String(failure)));
        }
      };
      try {
        const bridge = getBridge();
        const identity = session(bridge);
        if (bridge.hasNativeMethod && !bridge.hasNativeMethod(gateway, "asyn")) throw new MWBBridgeError(-1106, "Plugin gateway unavailable in this app");
        timer = setTimeout(() => complete(void 0, new MWBBridgeError(-1103, "MWB plugin call timed out")), timeoutMs);
        bridge.call(gateway, { ...identity, ...payload }, (value) => complete(value));
      } catch (error) {
        complete(void 0, error);
      }
    });
  }
  async function hasNativePlugin(name) {
    if (!validName(name)) throw new MWBBridgeError(-1102, "Invalid plugin name");
    const value = await invoke("mwb.pluginInfo", { plugin: name }, 3e4);
    if (typeof value.result?.available !== "boolean") throw new MWBBridgeError(-1102, "Invalid plugin availability response");
    return value.result.available;
  }
  function notifyPageReady() {
    return invoke("mwb.invokePlugin", {
      plugin: "basic",
      method: "notifyPageReady",
      params: null,
      callId: `mwb-${Date.now()}-${++nextCall}`,
      timeoutMs: 3e4
    }, 3e4);
  }
  function createNamespace(descriptor) {
    const functions = /* @__PURE__ */ new Map();
    const on = (name, handler) => {
      if (!validName(name) || methodReserved.has(name) || typeof handler !== "function") throw new MWBBridgeError(-1102, "Invalid plugin event subscription");
      const bridge = getBridge();
      const identity = session(bridge);
      return getEventHub(bridge).on("mwb.pluginEvent", (value) => {
        if (!value || typeof value !== "object") return;
        const event = value;
        if (event.plugin === descriptor.name && event.name === name && event.documentId === identity.documentId) {
          assertJSON(event.data);
          handler(event.data);
        }
      });
    };
    return new Proxy(/* @__PURE__ */ Object.create(null), {
      get(_target, property) {
        if (property === "on") return on;
        if (!validName(property) || methodReserved.has(property)) return void 0;
        if (!functions.has(property)) functions.set(property, (...args) => {
          try {
            if (args.length > 1) throw new MWBBridgeError(-1102, "Plugin methods accept one JSON parameter");
            const params = args[0] === void 0 ? null : args[0];
            assertJSON(params);
            return invoke("mwb.invokePlugin", {
              plugin: descriptor.name,
              method: property,
              params,
              callId: `mwb-${Date.now()}-${++nextCall}`,
              timeoutMs: descriptor.timeoutMs
            }, descriptor.timeoutMs);
          } catch (error) {
            return Promise.reject(error instanceof MWBBridgeError ? error : new MWBBridgeError(-1102, "Plugin parameters are not valid JSON"));
          }
        });
        return functions.get(property);
      }
    });
  }
  function attachNativePlugins(target, plugins) {
    for (const descriptor of plugins) {
      if (descriptor[descriptorBrand] !== true || !validName(descriptor.name) || reserved.has(descriptor.name)) throw new Error("Invalid MWB native plugin descriptor");
      if (Object.prototype.hasOwnProperty.call(target, descriptor.name)) throw new Error(`Duplicate MWB plugin: ${descriptor.name}`);
      Object.defineProperty(target, descriptor.name, { value: createNamespace(descriptor), enumerable: true });
    }
  }

  // src/plugins/container.ts
  var containerPlugin = {
    name: "container",
    methods: {
      notifyPageReady,
      setEnableDebug(enabled) {
        callSync("setEnableDebug", { enabled });
      },
      toast(param) {
        return callAsync("toast", param);
      },
      navigateTo(param) {
        return callAsync("navigateTo", param);
      },
      // 替换由原生一次完成，JS 不拼接打开和关闭操作。
      redirectTo(param) {
        return callAsync("redirectTo", param);
      },
      navigateBack(callbackInfo) {
        return callAsync("navigateBack", callbackInfo);
      },
      navigateBackToRoot() {
        return callAsync("navigateBackToRoot");
      },
      openExternalBrowser(param) {
        return callAsync("openExternalBrowser", param);
      },
      setNavigationBarTheme(param) {
        return callAsync("setNavigationBarTheme", param);
      },
      cleanWebviewCache() {
        return callAsync("cleanWebviewCache");
      },
      exitApp() {
        return callAsync("exitApp");
      },
      openNativePage(param) {
        return callAsync("openNativePage", param);
      }
    }
  };

  // src/plugins/device.ts
  var devicePlugin = {
    name: "device",
    methods: {
      openAppAuthorizeSetting() {
        return callAsync("openAppAuthorizeSetting");
      },
      getAppInfoSync() {
        return callSync("getAppInfoSync");
      },
      setBadgeCount(param) {
        return callAsync("setBadgeCount", param);
      },
      getDeviceInfoSync() {
        return callSync("getDeviceInfoSync");
      },
      getClipboardDataSync() {
        return callSync("getClipboardDataSync");
      },
      setClipboardData(param) {
        return callAsync("setClipboardData", param);
      },
      makePhoneCall(param) {
        return callAsync("makePhoneCall", param);
      },
      getNetworkTypeSync() {
        return callSync("getNetworkTypeSync");
      },
      getNotificationSwitchStatus() {
        return callAsync("getNotificationSwitchStatus");
      }
    }
  };

  // src/plugins/media.ts
  var mediaPlugin = {
    name: "media",
    methods: {
      compressImage(param) {
        return callAsync("compressImage", param);
      },
      scanCode(param) {
        return callAsync("scanCode", param);
      },
      saveImageToPhotosAlbum(param) {
        return callAsync("saveImageToPhotosAlbum", param);
      },
      chooseImage(param) {
        return callAsync("chooseImage", param);
      },
      openFile(param) {
        return callAsync("openFile", param);
      },
      checkRequestCameraPermissions(param) {
        return callAsync("checkRequestCameraPermissions", param);
      },
      convertImagePathToBase64(param) {
        return callAsync("convertImagePathToBase64", param);
      }
    }
  };

  // src/plugins/storage.ts
  var storagePlugin = {
    name: "storage",
    methods: {
      setStorageSync(key, data, groupName, validSecond) {
        callSync("setStorageSync", { key, data, groupName, validSecond });
      },
      getStorageSync(key, groupName) {
        const response = callSync("getStorageSync", { key, groupName });
        return response?.data;
      },
      removeStorageSync(key, groupName) {
        callSync("removeStorageSync", { key, groupName });
      },
      clearStorageSync(groupName) {
        callSync("clearStorageSync", { groupName });
      }
    }
  };

  // src/createMWB.ts
  var defaultPlugins = [containerPlugin, devicePlugin, mediaPlugin, storagePlugin];
  function createMWB(input = defaultPlugins) {
    const sdk = assembleMWB(Array.isArray(input) ? input : defaultPlugins);
    Object.assign(sdk, { hasPlugin: hasNativePlugin });
    if (!Array.isArray(input)) attachNativePlugins(sdk, input.plugins);
    return sdk;
  }

  // src/plugins/basic.ts
  var basicPlugin = {
    name: "basic",
    methods: { ...containerPlugin.methods, ...devicePlugin.methods, ...mediaPlugin.methods, ...storagePlugin.methods }
  };

  // src/index.ts
  var mwb = createMWB();

  // src/browser.ts
  window.mwb = mwb;
})();
