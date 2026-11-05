package com.mobilewebbridge.plugins

import org.junit.Assert.*
import org.junit.Test

/** 先证明当前 SDK 尚未提供可继承的插件入口。 */
class PluginApiTest {
    @Test fun hostCanAccessPluginBaseClass() {
        val pluginClass = runCatching { Class.forName("com.mobilewebbridge.plugins.MWBPlugin") }.getOrNull()
        assertNotNull("宿主应能继承 MWBPlugin，而无需注册 DSBridge 对象", pluginClass)
    }
    @Test fun bridgeExposesSeparatePluginGateways() {
        val names = com.mobilewebbridge.MWBBridgeAdapter::class.java.declaredMethods.map { it.name }.toSet()
        assertTrue("业务插件不能依赖旧 basic 方法表", names.containsAll(setOf("pluginSession", "pluginInfo", "invokePlugin")))
    }
}
