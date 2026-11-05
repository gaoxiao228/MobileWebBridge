package com.mobilewebbridge.plugins

import android.app.Activity

/** 只读文档身份；Activity 访问器由会话弱引用且仅在当前文档有效。 */
class MWBPluginCallContext internal constructor(
    val containerId: String,
    val documentId: String,
    val pageUrl: String,
    private val activityProvider: () -> Activity?,
    private val eventSender: (String, Any?) -> Unit,
    private val cancellation: PluginCancellation
) {
    val activity: Activity? get() = activityProvider()
    fun emit(name: String, data: Any? = null) = eventSender(name, data)
    fun onCancel(handler: () -> Unit) = cancellation.register(handler)
}

/** 取消注册和完成竞争由会话主线程统一处理，晚注册也会立即观察取消。 */
internal class PluginCancellation(private val onMain: (() -> Unit) -> Unit) {
    private var cancelled = false
    private var completed = false
    private val handlers = mutableListOf<() -> Unit>()
    fun register(handler: () -> Unit) = onMain {
        if (cancelled) runCatching(handler) else if (!completed) handlers.add(handler)
    }
    fun cancel() {
        if (cancelled || completed) return
        cancelled = true
        val callbacks = handlers.toList(); handlers.clear()
        callbacks.forEach { runCatching(it) }
    }
    fun complete() { completed = true; handlers.clear() }
}
