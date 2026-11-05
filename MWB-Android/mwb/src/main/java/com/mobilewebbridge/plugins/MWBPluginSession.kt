package com.mobilewebbridge.plugins

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.mobilewebbridge.MWBResult
import org.json.JSONObject
import java.util.UUID

/** 每容器独立会话；所有业务调用、完成、事件及清理按主线程顺序执行。 */
internal class MWBPluginSession(
    private val factories: Map<String, () -> MWBPlugin>,
    private val trusted: () -> Boolean,
    private val activity: () -> Activity?,
    private val sendEvent: (JSONObject) -> Unit
) {
    /** 内置能力由容器安装，调用仍须先通过文档身份校验。 */
    var notifyPageReady: (() -> JSONObject)? = null
    private val main = Handler(Looper.getMainLooper())
    private val containerId = UUID.randomUUID().toString()
    @Volatile private var documentId: String? = null
    @Volatile private var pageUrl = ""
    private val instances = mutableMapOf<String, MWBPlugin>()
    private class Pending(val document: String, var callback: ((JSONObject) -> Unit)?,
                          val cancellation: PluginCancellation, val deadline: Long) {
        lateinit var timeout: Runnable
    }
    private val pending = mutableMapOf<String, Pending>()
    private fun onMain(action: () -> Unit) { if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post(action) }

    fun beginDocument(url: String) {
        invalidate(); pageUrl = url; documentId = UUID.randomUUID().toString()
    }
    fun invalidate() {
        // 首先撤销身份，使 dispose/cancel 内的重入事件无法触达任何新文档。
        documentId = null
        val calls = pending.values.toList(); pending.clear()
        calls.forEach { main.removeCallbacks(it.timeout); it.callback = null; it.cancellation.cancel() }
        val plugins = instances.values.toList(); instances.clear()
        plugins.forEach { runCatching { it.dispose() } }
    }
    internal fun replyDocumentId(): String? = if (trusted()) documentId else null

    fun session(): JSONObject {
        if (!trusted()) return MWBResult.failure(-1006, "Untrusted page")
        val document = documentId ?: return MWBResult.failure(-1104, "Document is no longer active")
        return MWBResult.success(JSONObject().put("protocol", 1).put("documentId", document))
    }
    private fun validate(arg: Any?): JSONObject? {
        if (!trusted()) return MWBResult.failure(-1006, "Untrusted page")
        val obj = arg as? JSONObject ?: return MWBResult.failure(-1102, "Invalid plugin request")
        if (obj.opt("protocol") !is Number || obj.optDouble("protocol") != 1.0)
            return MWBResult.failure(-1106, "Unsupported plugin protocol")
        if (documentId == null || obj.opt("documentId") != documentId)
            return MWBResult.failure(-1104, "Document is no longer active")
        val plugin = obj.opt("plugin") as? String
        if (plugin == null || (plugin != "basic" && !PluginNames.plugin(plugin)))
            return MWBResult.failure(-1102, "Invalid plugin name")
        return null
    }
    fun info(arg: Any?, callback: (JSONObject) -> Unit) {
        val enteredDocument = documentId
        onMain {
            if (documentId != enteredDocument) return@onMain
            val error = validate(arg)
            if (error != null) callback(error)
            else {
                val name = (arg as JSONObject).getString("plugin")
                callback(MWBResult.success(JSONObject().put("available", name == "basic" || name in factories)))
            }
        }
    }
    fun invoke(arg: Any?, callback: (JSONObject) -> Unit) {
        val enteredDocument = documentId
        onMain {
            if (documentId != enteredDocument) return@onMain
            val error = validate(arg)
            if (error != null) { callback(error); return@onMain }
            val obj = arg as JSONObject
            val method = obj.opt("method") as? String
            val callId = obj.opt("callId") as? String
            val timeoutValue = if (obj.has("timeoutMs")) obj.opt("timeoutMs") else 30000
            val timeout = (timeoutValue as? Number)?.toDouble()
            if (method == null || !PluginNames.method(method) || callId.isNullOrBlank() || callId in pending ||
                timeout == null || !timeout.isFinite() || timeout % 1.0 != 0.0 || timeout !in 1.0..120000.0) {
                callback(MWBResult.failure(-1102, "Invalid plugin call parameters")); return@onMain
            }
            val params = runCatching { PluginJson.copy(obj.opt("params")) }.getOrElse {
                callback(MWBResult.failure(-1102, "Plugin parameters are not JSON")); return@onMain
            }
            val name = obj.getString("plugin")
            if (name == "basic") {
                val result = when {
                    method != "notifyPageReady" -> MWBResult.failure(-1101, "Builtin method is unsupported")
                    params != JSONObject.NULL -> MWBResult.failure(-1102, "notifyPageReady takes no parameters")
                    else -> notifyPageReady?.invoke() ?: MWBResult.failure(-1106, "Page readiness is unavailable")
                }
                callback(result)
                return@onMain
            }
            val factory = factories[name]
            if (factory == null) {
                callback(MWBResult.failure(if (name == "basic") -1101 else -1100, "Plugin is not available")); return@onMain
            }
            val document = documentId!!
            val cancellation = PluginCancellation(::onMain)
            val call = Pending(document, callback, cancellation, SystemClock.uptimeMillis() + timeout.toLong())
            call.timeout = Runnable { finish(callId, call, MWBResult.failure(-1103, "Plugin call timed out"), true) }
            pending[callId] = call; main.postDelayed(call.timeout, timeout.toLong())
            val context = MWBPluginCallContext(containerId, document, pageUrl,
                { if (documentId == document && trusted()) activity() else null },
                { event, data -> emit(document, name, event, data) }, cancellation)
            val responder = MWBPluginResponder { value -> onMain {
                val expired = SystemClock.uptimeMillis() >= call.deadline
                finish(callId, call, if (expired) MWBResult.failure(-1103, "Plugin call timed out") else value, expired)
            } }
            try {
                val plugin = instances[name] ?: factory().let { created ->
                    // 宿主工厂可能同步导航；旧实例不得写入新文档或继续执行业务。
                    if (documentId != document || !trusted()) {
                        runCatching { created.dispose() }
                        finish(callId, call, MWBResult.failure(-1104, "Document is no longer active"), true)
                        return@onMain
                    }
                    instances[name] = created
                    created
                }
                if (SystemClock.uptimeMillis() >= call.deadline) call.timeout.run()
                else plugin.handle(method, params, context, responder)
            } catch (_: Exception) { responder.failure(-1105, "Plugin initialization or execution failed") }
        }
    }
    private fun finish(id: String, call: Pending, response: JSONObject, cancel: Boolean) {
        if (pending[id] !== call) return
        pending.remove(id); main.removeCallbacks(call.timeout)
        if (cancel) call.cancellation.cancel() else call.cancellation.complete()
        val callback = call.callback
        call.callback = null
        if (documentId == call.document && trusted()) callback?.invoke(response)
    }
    private fun emit(document: String, plugin: String, name: String, data: Any?) {
        if (!PluginNames.method(name)) return
        val json = runCatching { PluginJson.copy(data) }.getOrNull() ?: return
        onMain {
            if (documentId == document && trusted()) sendEvent(JSONObject().put("documentId", document)
                .put("plugin", plugin).put("name", name).put("data", json))
        }
    }
}
