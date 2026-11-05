package com.mobilewebbridge

import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/** 使用真实 Activity 和插件网关，验证状态终态、就绪去重及容器隔离。 */
@RunWith(RobolectricTestRunner::class)
class PageLifecycleTest {
    class ObservedActivity : MWBActivity() {
        val states = mutableListOf<MWBLoadState>()
        var readyCount = 0
        override fun onCreate(savedInstanceState: Bundle?) {
            // 必须能在 super.onCreate 触发首次自动加载前安装回调。
            onLoadStateChange = { states.add(it) }
            onPageReady = { readyCount++ }
            super.onCreate(savedInstanceState)
        }
    }
    private fun container() = Robolectric.buildActivity(ObservedActivity::class.java,
        MWBActivity.createIntent(ApplicationProvider.getApplicationContext(),
            MWBConfiguration("file:///android_asset/index.html", emptySet()))).setup()
    private fun ready(activity: MWBActivity, document: String = document(activity)): Int {
        var code: Int? = null
        activity.pluginSession.invoke(JSONObject().put("protocol", 1).put("documentId", document)
            .put("plugin", "basic").put("method", "notifyPageReady").put("params", JSONObject.NULL)
            .put("callId", java.util.UUID.randomUUID().toString())) { code = it.getInt("errCode") }
        return code!!
    }
    private fun document(activity: MWBActivity) = activity.pluginSession.session()
        .getJSONObject("result").getString("documentId")

    @Test fun firstLoadIsObservableAndReadyCanPrecedeLoadFinish() {
        val controller = container(); val activity = controller.get(); val view = activity.webView!!
        assertEquals(listOf(MWBLoadState.LOADING), activity.states)
        assertFalse(activity.isPageReady)
        assertEquals(0, ready(activity)); assertEquals(0, ready(activity))
        assertTrue(activity.isPageReady); assertEquals(1, activity.readyCount)
        shadowOf(view).webViewClient.onPageFinished(view, "file:///android_asset/index.html")
        assertEquals(MWBLoadState.LOADED, activity.loadState)
        assertTrue(activity.isPageReady)
        assertEquals(listOf(MWBLoadState.LOADING, MWBLoadState.LOADED), activity.states)
        controller.pause().stop().destroy()
    }
    @Test fun reloadAndDocumentReplacementRejectOldReadinessAndKeepContainersIndependent() {
        val first = container(); val second = container(); val activity = first.get()
        val old = document(activity)
        ready(activity); assertFalse(second.get().isPageReady)
        activity.reload()
        assertFalse(activity.isPageReady); assertEquals(MWBLoadState.LOADING, activity.loadState)
        assertNotEquals(0, ready(activity, old))
        val view = activity.webView!!
        shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/index.html", null)
        assertNotEquals(old, document(activity))
        assertEquals(-1104, ready(activity, old))
        ready(activity); assertEquals(2, activity.readyCount)
        first.pause().stop().destroy(); second.pause().stop().destroy()
        assertFalse(activity.isPageReady)
    }
    @Test fun mainFrameFailureCannotBeOverwrittenByLatePageFinished() {
        val controller = container(); val activity = controller.get(); val view = activity.webView!!
        val client = shadowOf(view).webViewClient
        val request = request("file:///android_asset/index.html")
        val error = android.webkit.TestWebResourceError()
        ready(activity)
        client.onReceivedError(view, request, error)
        client.onPageFinished(view, "file:///android_asset/index.html")
        assertEquals(MWBLoadState.FAILED, activity.loadState)
        assertEquals("network failed", activity.loadError)
        assertFalse(activity.isPageReady)
        controller.pause().stop().destroy()
    }
    @Test fun absentCallbacksStillRecordReadinessAndBlockedNavigationKeepsCurrentPage() {
        val controller = container(); val activity = controller.get(); val view = activity.webView!!
        activity.onPageReady = null; activity.onLoadStateChange = null
        assertEquals(0, ready(activity)); assertTrue(activity.isPageReady)
        assertTrue(shadowOf(view).webViewClient.shouldOverrideUrlLoading(view, "https://untrusted.example/"))
        assertTrue(activity.isPageReady)
        assertFalse(activity.load("https://untrusted.example/"))
        assertTrue(activity.isPageReady)
        controller.pause().stop().destroy()
    }

    @Test fun staleOtherUrlCallbacksAndSubresourceErrorsDoNotAffectNewDocument() {
        val controller = container(); val activity = controller.get(); val view = activity.webView!!
        val client = shadowOf(view).webViewClient
        activity.load("file:///android_asset/next.html")
        client.onPageStarted(view, "file:///android_asset/next.html", null)
        client.onPageFinished(view, "file:///android_asset/index.html")
        assertEquals(MWBLoadState.LOADING, activity.loadState)
        val resource = request("file:///android_asset/next.html", false)
        client.onReceivedError(view, resource, android.webkit.TestWebResourceError())
        assertEquals(MWBLoadState.LOADING, activity.loadState)
        client.onReceivedError(view, request("file:///android_asset/index.html"), android.webkit.TestWebResourceError())
        assertEquals(MWBLoadState.LOADING, activity.loadState)
        controller.pause().stop().destroy()
    }
    @Test fun httpMainFrameErrorIsTerminalAndRejectsReadiness() {
        val controller = container(); val activity = controller.get(); val view = activity.webView!!
        val old = document(activity); val client = shadowOf(view).webViewClient
        client.onReceivedHttpError(view, request("file:///android_asset/index.html"),
            android.webkit.WebResourceResponse("text/html", "UTF-8", 503, "Unavailable", emptyMap(), null))
        client.onPageFinished(view, "file:///android_asset/index.html")
        assertEquals(MWBLoadState.FAILED, activity.loadState)
        assertTrue(activity.loadError!!.contains("503"))
        assertNotEquals(0, ready(activity, old))
        controller.pause().stop().destroy()
    }
    @Test fun readyCallbackCanReloadWithoutOldStateBeingWrittenBack() {
        val controller = container(); val activity = controller.get()
        activity.onPageReady = { activity.reload() }
        ready(activity)
        assertFalse(activity.isPageReady)
        assertEquals(MWBLoadState.LOADING, activity.loadState)
        controller.pause().stop().destroy()
    }
    private fun request(url: String, main: Boolean = true) = object : android.webkit.WebResourceRequest {
        override fun getUrl() = android.net.Uri.parse(url)
        override fun isForMainFrame() = main
        override fun isRedirect() = false
        override fun hasGesture() = false
        override fun getMethod() = "GET"
        override fun getRequestHeaders() = emptyMap<String, String>()
    }
}
