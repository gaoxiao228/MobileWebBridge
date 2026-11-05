package com.mobilewebbridge.plugins

import com.mobilewebbridge.MWBBridgeAdapter
import java.util.Collections

/** 名称规则在注册、调用和事件三个入口保持一致。 */
internal object PluginNames {
    private val syntax = Regex("[a-z][a-zA-Z0-9_]*")
    private val probes = setOf("on", "then", "catch", "finally", "toJSON", "inspect", "constructor", "prototype", "__proto__")
    private val roots = MWBBridgeAdapter.nativeMethods + setOf(
        "notifyPageReady", "basic", "version", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin", "pluginEvent", "dispatchEvent", "backBtnPressed",
        "registerHandler", "unRegisterHandlers", "unRegisterHandler", "checkHandlerExist",
        "onNetworkStatusChange", "offNetworkStatusChange", "onAppShow", "offAppShow", "onAppHide", "offAppHide",
        "onRemoteNotificationReceive", "offRemoteNotificationReceive", "onPageShow", "offPageShow", "onPageHide", "offPageHide",
        "onBackBtnPressed", "offBackBtnPressed")
    fun method(name: String): Boolean = syntax.matches(name) && name !in probes
    fun plugin(name: String): Boolean = method(name) && name !in roots
}

/** 在第一个容器创建时冻结；测试可自行创建独立注册表，不提供全局重置入口。 */
internal class MWBPluginRegistry {
    private val factories = linkedMapOf<String, () -> MWBPlugin>()
    private var frozen = false
    @Synchronized fun register(name: String, factory: () -> MWBPlugin) {
        check(!frozen) { "Register plugins before creating the first MWB container" }
        require(PluginNames.plugin(name)) { "Invalid or reserved plugin name: $name" }
        require(name !in factories) { "Duplicate plugin name: $name" }
        factories[name] = factory
    }
    @Synchronized fun snapshot(): Map<String, () -> MWBPlugin> {
        frozen = true
        return Collections.unmodifiableMap(LinkedHashMap(factories))
    }
}
