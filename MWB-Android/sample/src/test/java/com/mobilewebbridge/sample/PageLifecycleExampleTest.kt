package com.mobilewebbridge.sample

import android.app.Application
import android.content.Intent
import android.os.Looper
import com.mobilewebbridge.MWBBridgeAdapter
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLog
import wendu.dsbridge.CompletionHandler

/** 示例必须在首次加载前安装闭包，并通过真实网关验证重复报告只通知一次。 */
@RunWith(RobolectricTestRunner::class)
// 使用独立的 API 28 沙箱，同时验证较低系统版本，隔离进程级插件注册表。
@Config(application = Application::class, sdk = [28])
class PageLifecycleExampleTest {
    @Test fun sampleRegistersBeforeLoadingAndLogsOneReadyCallbackPerDocument() {
        ShadowLog.clear()
        val controller = Robolectric.buildActivity(SampleWebActivity::class.java, Intent()).setup()
        try {
            val activity = controller.get()
            assertNotNull(activity.onLoadStateChange)
            assertNotNull(activity.onPageReady)
            assertTrue(ShadowLog.getLogsForTag("MWB-Lifecycle").any { it.msg.contains("loadState=loading") })
            val adapter = MWBBridgeAdapter(activity)
            fun notifyReady(callId: String) {
                val session = (adapter.pluginSession(JSONObject.NULL) as JSONObject).getJSONObject("result")
                val args = JSONObject().put("protocol", 1).put("documentId", session.getString("documentId"))
                    .put("plugin", "basic").put("method", "notifyPageReady").put("callId", callId).put("params", JSONObject.NULL)
                var code: Int? = null
                adapter.invokePlugin(args, object : CompletionHandler<Any> {
                    override fun complete(value: Any?) { code = (value as JSONObject).getInt("errCode") }
                    override fun complete() { fail("Expected response") }
                    override fun setProgressData(value: Any?) { fail("Unexpected progress") }
                })
                shadowOf(Looper.getMainLooper()).idle()
                assertEquals(0, code)
            }
            notifyReady("first")
            notifyReady("duplicate")
            assertTrue(activity.isPageReady)
            assertEquals(1, ShadowLog.getLogsForTag("MWB-Lifecycle").count { it.msg.contains("pageReady count=") })
            activity.reload()
            assertFalse(activity.isPageReady)
            // Robolectric 不执行网页导航，显式投递系统的主文档开始回调。
            val view = activity.webView!!
            shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/index.html", null)
            notifyReady("reloaded")
            assertTrue(ShadowLog.getLogsForTag("MWB-Lifecycle").any { it.msg.contains("pageReady count=2") })
        } finally { controller.pause().stop().destroy() }
    }
}
