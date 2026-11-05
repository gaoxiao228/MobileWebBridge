package com.mobilewebbridge.plugins

import android.os.Looper
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/** 覆盖真实注册、方法分发和文档隔离，避免依赖外网或设备。 */
@RunWith(RobolectricTestRunner::class)
class PluginSessionTest {
    class Echo : MWBPlugin() {
        var disposed = false
        var responder: MWBPluginResponder? = null
        var context: MWBPluginCallContext? = null
        @MWBMethod fun echo(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
            responder.success(params); responder.failure(99, "duplicate")
        }
        @MWBMethod fun wait(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
            this.responder = responder; this.context = context
        }
        fun helper(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) { responder.success("secret") }
        override fun dispose() { disposed = true }
    }
    class Overload : MWBPlugin() {
        @MWBMethod fun request(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) { responder.success() }
        @MWBMethod fun request(params: String) { }
    }
    class Bad : MWBPlugin() { @MWBMethod fun wrong(value: String) = value }
    private fun request(session: MWBPluginSession, method: String = "echo", params: Any? = JSONObject.NULL,
                        timeout: Int = 30000, callId: String = "call"): JSONObject = JSONObject()
        .put("protocol", 1).put("documentId", session.session().getJSONObject("result").getString("documentId"))
        .put("plugin", "echo").put("method", method).put("params", params).put("callId", callId).put("timeoutMs", timeout)
    private fun session(factory: () -> MWBPlugin = { Echo() }, events: MutableList<JSONObject> = mutableListOf()): MWBPluginSession {
        val registry = MWBPluginRegistry(); registry.register("echo", factory)
        return MWBPluginSession(registry.snapshot(), { true }, { null }) { events.add(it) }.apply {
            beginDocument("https://example.com/")
        }
    }
    @Test fun onlyAnnotatedMethodsAreCallableAndNullRemainsExplicit() {
        val session = session(); val results = mutableListOf<JSONObject>()
        session.invoke(request(session)) { results.add(it) }
        assertEquals(1, results.size); assertTrue(results.single().has("result")); assertTrue(results.single().isNull("result"))
        session.invoke(request(session, "helper")) { assertEquals(-1101, it.getInt("errCode")) }
        session.invoke(request(session, "missing")) { assertEquals(-1101, it.getInt("errCode")) }
    }
    @Test fun registryRejectsConflictsAndFreezesWithoutCreatingPlugins() {
        var created = 0; val registry = MWBPluginRegistry()
        for (name in listOf("basic", "version", "navigateTo", "hasPlugin", "pluginSession", "pluginInfo", "invokePlugin",
            "pluginEvent", "dispatchEvent", "backBtnPressed", "registerHandler", "unRegisterHandlers", "unRegisterHandler",
            "checkHandlerExist", "onNetworkStatusChange", "offNetworkStatusChange", "onAppShow", "offAppShow", "onAppHide",
            "offAppHide", "onRemoteNotificationReceive", "offRemoteNotificationReceive", "onPageShow", "offPageShow",
            "onPageHide", "offPageHide", "onBackBtnPressed", "offBackBtnPressed", "on", "then", "catch", "finally",
            "toJSON", "inspect", "constructor", "prototype", "__proto__", "Bad"))
            assertThrows(IllegalArgumentException::class.java) { registry.register(name) { Echo() } }
        // 非 SDK 根成员不能额外禁止，否则 JS 与两端原生允许的插件名会分叉。
        registry.register("callHandler") { Echo() }
        registry.register("echo") { created++; Echo() }
        assertThrows(IllegalArgumentException::class.java) { registry.register("echo") { Echo() } }
        val session = MWBPluginSession(registry.snapshot(), { true }, { null }) { }
        session.beginDocument("https://example.com/")
        session.info(request(session)) { assertTrue(it.getJSONObject("result").getBoolean("available")) }
        assertEquals(0, created)
        assertThrows(IllegalStateException::class.java) { registry.register("other") { Echo() } }
    }
    @Test fun timeoutCancelsOnceAndIgnoresLateCompletion() {
        val echo = Echo(); val session = session({ echo }); val results = mutableListOf<JSONObject>(); var cancelled = 0
        session.invoke(request(session, "wait", timeout = 5)) { results.add(it) }
        echo.context!!.onCancel { cancelled++ }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(6))
        echo.responder!!.success("late")
        assertEquals(1, cancelled); assertEquals(listOf(-1103), results.map { it.getInt("errCode") })
        echo.context!!.onCancel { cancelled++ }; assertEquals(2, cancelled)
    }
    @Test fun navigationDisposesCancelsAndBlocksOldEventsAndCallbacks() {
        val echo = Echo(); val events = mutableListOf<JSONObject>(); val session = session({ echo }, events)
        val oldRequest = request(session, "wait"); var completed = false; var cancelled = false
        session.invoke(oldRequest) { completed = true }
        echo.context!!.onCancel { cancelled = true }
        echo.context!!.emit("ready", JSONObject().put("value", 1))
        assertEquals(1, events.size)
        session.beginDocument("https://example.com/next")
        assertTrue(echo.disposed); assertTrue(cancelled)
        echo.responder!!.success("late"); echo.context!!.emit("ready", "late")
        assertFalse(completed); assertEquals(1, events.size)
        session.invoke(oldRequest) { assertEquals(-1104, it.getInt("errCode")) }
    }
    @Test fun backgroundEntryAndCompletionRunOnMainAndNeverCompleteTwice() {
        val echo = Echo(); val session = session({ echo }); val results = mutableListOf<JSONObject>()
        val arg = request(session, "wait")
        Thread { session.invoke(arg) { results.add(it) } }.apply { start(); join() }
        assertNull(echo.context)
        shadowOf(Looper.getMainLooper()).idle()
        assertNotNull(echo.context)
        Thread { echo.responder!!.success("worker"); echo.responder!!.success("again") }.apply { start(); join() }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("worker"), results.map { it.getString("result") })
    }
    @Test fun invalidResultsAndEventsAreBlockedAndUntrustedPagesCannotUseTheGateway() {
        val echo = Echo(); val events = mutableListOf<JSONObject>(); var trusted = true
        val registry = MWBPluginRegistry(); registry.register("echo") { echo }
        val session = MWBPluginSession(registry.snapshot(), { trusted }, { null }) { events.add(it) }
        session.beginDocument("https://example.com/")
        val arg = request(session, "wait")
        val responses = mutableListOf<JSONObject>()
        session.invoke(arg) { responses.add(it) }
        echo.context!!.emit("ready", Any()); echo.context!!.emit("then", "secret")
        assertEquals(0, events.size)
        echo.responder!!.success(Any())
        assertEquals(-1102, responses.single().getInt("errCode"))
        val cycle = JSONObject(); cycle.put("self", cycle)
        session.invoke(request(session, params = cycle)) { assertEquals(-1102, it.getInt("errCode")) }
        trusted = false
        echo.context!!.emit("ready", "secret")
        assertEquals(-1006, session.session().getInt("errCode"))
        session.invoke(arg) { assertEquals(-1006, it.getInt("errCode")) }
        session.info(arg) { assertEquals(-1006, it.getInt("errCode")) }
        assertEquals(0, events.size)
    }
    @Test fun containerSnapshotsCreateIndependentInstancesWithSharedFactoryService() {
        var created = 0; val plugins = mutableListOf<Echo>(); val registry = MWBPluginRegistry()
        registry.register("echo") { created++; Echo().also { plugins.add(it) } }
        val snapshot = registry.snapshot()
        val first = MWBPluginSession(snapshot, { true }, { null }) { }
        val second = MWBPluginSession(snapshot, { true }, { null }) { }
        first.beginDocument("https://example.com/"); second.beginDocument("https://example.com/child")
        first.invoke(request(first, "wait")) { }
        second.invoke(request(second, "wait")) { }
        assertEquals(2, created); assertNotSame(plugins[0], plugins[1])
        first.invalidate()
        assertTrue(plugins[0].disposed); assertFalse(plugins[1].disposed)
        assertNotEquals(plugins[0].context!!.documentId, plugins[1].context!!.documentId)
    }
    @Test fun factoryNavigationCannotRunOldMethodOrStoreOldInstanceInNewDocument() {
        lateinit var session: MWBPluginSession
        val created = mutableListOf<Echo>()
        session = session({
            Echo().also {
                created.add(it)
                if (created.size == 1) session.beginDocument("https://example.com/new")
            }
        })
        var oldCompleted = false
        session.invoke(request(session, "wait")) { oldCompleted = true }
        assertTrue(created[0].disposed)
        assertNull(created[0].context)
        assertFalse(oldCompleted)
        session.invoke(request(session, "wait")) { }
        assertEquals(2, created.size)
        assertNotNull(created[1].context)
    }
    @Test fun factoryTimeIsPartOfTimeoutAndOverloadsAreConfigurationErrors() {
        val slow = session({
            org.robolectric.shadows.ShadowSystemClock.advanceBy(Duration.ofMillis(20))
            Echo()
        })
        slow.invoke(request(slow, timeout = 10)) { assertEquals(-1103, it.getInt("errCode")) }
        val overloaded = session({ Overload() })
        overloaded.invoke(request(overloaded, "request")) { assertEquals(-1105, it.getInt("errCode")) }
    }
    @Test fun invalidWireJsonAndFactoryFailuresHaveExplicitErrors() {
        val session = session()
        for ((key, value, code) in listOf(Triple("protocol", 2, -1106), Triple("timeoutMs", 0, -1102),
            Triple("plugin", "unknown", -1100), Triple("method", "then", -1102), Triple("params", Any(), -1102))) {
            session.invoke(request(session).put(key, value)) { assertEquals(key, code, it.getInt("errCode")) }
        }
        val bad = session({ Bad() }); bad.invoke(request(bad, "wrong")) { assertEquals(-1105, it.getInt("errCode")) }
        val broken = session({ error("factory") }); broken.invoke(request(broken)) { assertEquals(-1105, it.getInt("errCode")) }
    }

    @Test fun builtinReadinessValidatesParametersAndRunsOnMainThread() {
        val session = session(); var notifications = 0
        session.notifyPageReady = { assertEquals(Looper.getMainLooper(), Looper.myLooper()); notifications++; com.mobilewebbridge.MWBResult.success() }
        val request = request(session, "notifyPageReady").put("plugin", "basic")
        val results = mutableListOf<JSONObject>()
        Thread { session.invoke(request) { results.add(it) } }.apply { start(); join() }
        assertEquals(0, notifications)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, notifications); assertEquals(0, results.single().getInt("errCode"))
        session.invoke(JSONObject(request.toString()).put("params", JSONObject())) { assertEquals(-1102, it.getInt("errCode")) }
        assertEquals(1, notifications)
        assertThrows(IllegalArgumentException::class.java) {
            MWBPluginRegistry().register("notifyPageReady") { Echo() }
        }
    }
}
