package com.mobilewebbridge

import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.Button
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/** 验证真实容器的恢复操作，不依赖错误页内部布局实现。 */
@RunWith(RobolectricTestRunner::class)
class ErrorPageTest {
    private fun container(enabled: Boolean = true, entry: String = "index.html") = Robolectric.buildActivity(MWBActivity::class.java,
        MWBActivity.createIntent(ApplicationProvider.getApplicationContext(),
            MWBConfiguration("file:///android_asset/missing.html", emptySet(), MWBErrorPageConfiguration(enabled, entry = entry)))).setup()
    private fun request(method: String = "GET", main: Boolean = true, url: String = "file:///android_asset/missing.html") = object : WebResourceRequest {
        override fun getUrl() = android.net.Uri.parse(url)
        override fun isForMainFrame() = main
        override fun isRedirect() = false
        override fun hasGesture() = true
        override fun getMethod() = method
        override fun getRequestHeaders() = emptyMap<String, String>()
    }
    private fun fail(activity: MWBActivity, method: String = "GET", main: Boolean = true) {
        val view = activity.webView!!
        shadowOf(view).webViewClient.onReceivedError(view, request(method, main), android.webkit.TestWebResourceError())
    }
    private fun views(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun button(activity: MWBActivity, text: String) = views(activity.window.decorView)
        .filterIsInstance<Button>().first { it.text == text }
    private fun overlay(activity: MWBActivity): View? = activity.window.decorView.findViewWithTag("mwb-error-overlay")

    @Test fun defaultFailureAndDisabledMode() {
        val c = container(); val a = c.get(); fail(a)
        assertEquals(MWBLoadState.FAILED, a.loadState); assertNotNull(overlay(a)); assertFalse(a.isPageReady)
        assertEquals(MWBPageLoadError.Kind.localResource, a.errorPageError?.kind)
        c.pause().stop().destroy()
        val disabled = container(false); fail(disabled.get())
        assertNull(overlay(disabled.get())); assertEquals(MWBLoadState.FAILED, disabled.get().loadState)
        disabled.pause().stop().destroy()
    }
    @Test fun subresourceAndCancelIgnored() {
        val c = container(); fail(c.get(), main = false)
        assertEquals(MWBLoadState.LOADING, c.get().loadState); assertNull(overlay(c.get()))
        c.pause().stop().destroy()
    }
    @Test fun retryUsesFailedGETAndRejectsOldViewCallbacks() {
        val c = container(); val a = c.get(); val old = a.webView!!; val oldClient = shadowOf(old).webViewClient
        fail(a); button(a, "重新加载").performClick()
        val fresh = a.webView!!
        assertNotSame(old, fresh); assertEquals("file:///android_asset/missing.html", fresh.url)
        assertEquals(MWBLoadState.LOADING, a.loadState); assertFalse(button(a, "正在重新加载…").isEnabled)
        oldClient.onPageFinished(old, "file:///android_asset/missing.html")
        oldClient.onReceivedError(old, request(), android.webkit.TestWebResourceError())
        assertEquals(MWBLoadState.LOADING, a.loadState)
        shadowOf(fresh).webViewClient.onPageStarted(fresh, "file:///android_asset/missing.html", null)
        shadowOf(fresh).webViewClient.onPageFinished(fresh, "file:///android_asset/missing.html")
        assertEquals(MWBLoadState.LOADED, a.loadState); assertNull(overlay(a))
        c.pause().stop().destroy()
    }
    @Test fun backFromFailureRestoresBusinessHistory() {
        val c = container(); val a = c.get(); val view = a.webView!!
        shadowOf(view).pushEntryToHistory("file:///android_asset/index.html")
        shadowOf(view).pushEntryToHistory("file:///android_asset/missing.html")
        fail(a)
        a.onBackPressed()
        assertNull(overlay(a)); assertNull(a.errorPageError)
        assertEquals(MWBLoadState.LOADING, a.loadState)
        assertNotSame(view, a.webView)
        assertEquals(View.VISIBLE, a.webView!!.visibility)
        assertEquals(1, shadowOf(a.webView!!).goBackInvocations)
        c.pause().stop().destroy()
    }
    @Test fun explicitLoadAfterFailureRejectsOldSameURLErrors() {
        val c = container(); val a = c.get(); val old = a.webView!!; val client = shadowOf(old).webViewClient
        fail(a)
        a.load("file:///android_asset/missing.html")
        client.onReceivedError(old, request(), android.webkit.TestWebResourceError())
        assertEquals(MWBLoadState.LOADING, a.loadState); assertNull(a.errorPageError)
        assertNotSame(old, a.webView)
        c.pause().stop().destroy()
    }
    @Test fun backAfterFailureRejectsOldSameURLErrors() {
        val c = container(); val a = c.get(); val old = a.webView!!; val client = shadowOf(old).webViewClient
        shadowOf(old).pushEntryToHistory("file:///android_asset/index.html")
        shadowOf(old).pushEntryToHistory("file:///android_asset/missing.html")
        fail(a); a.onBackPressed()
        client.onReceivedError(old, request(), android.webkit.TestWebResourceError())
        assertEquals(MWBLoadState.LOADING, a.loadState); assertNull(a.errorPageError)
        assertNotSame(old, a.webView)
        c.pause().stop().destroy()
    }
    @Test fun mainFrameHTTPFailureCannotBecomeBlankReadyPage() {
        val c = container(); val a = c.get(); fail(a)
        val page = views(a.window.decorView).filterIsInstance<WebView>().first { it !== a.webView }
        val client = shadowOf(page).webViewClient
        val response = android.webkit.WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(), java.io.ByteArrayInputStream(byteArrayOf()))
        client.onReceivedHttpError(page, request(url = page.url!!), response)
        client.onPageFinished(page, page.url!!)
        assertNull(page.parent); assertNotNull(overlay(a))
        assertTrue(button(a, "重新加载").isEnabled)
        c.pause().stop().destroy()
    }
    @Test fun customEntryUsesCanonicalEncodedURL() {
        val c = container(entry = "页面/错误 页.html"); val a = c.get(); fail(a)
        val page = views(a.window.decorView).filterIsInstance<WebView>().first { it !== a.webView }
        assertTrue(page.url!!.endsWith("/%E9%A1%B5%E9%9D%A2/%E9%94%99%E8%AF%AF%20%E9%A1%B5.html"))
        c.pause().stop().destroy()
    }
    @Test fun postIsNeverReplayed() {
        val c = container(); val a = c.get(); fail(a, "POST")
        assertFalse(button(a, "重新加载").isEnabled)
        c.pause().stop().destroy()
    }
    @Test fun homeCancelsRetryBeforeCallbackAndAllowsReentrantLoad() {
        val c = container(); val a = c.get(); var count = 0
        a.onGoHome = { current ->
            assertSame(a, current); assertEquals(Looper.getMainLooper(), Looper.myLooper())
            assertEquals(MWBLoadState.FAILED, current.loadState)
            count++; current.load("file:///android_asset/index.html")
        }
        fail(a); button(a, "重新加载").performClick(); button(a, "回到首页").performClick()
        assertEquals(1, count); assertEquals(MWBLoadState.LOADING, a.loadState)
        assertEquals("file:///android_asset/index.html", a.webView?.url); assertNull(overlay(a))
        c.pause().stop().destroy()
    }
    @Test fun reentrantFailureCallbackDoesNotCoverNewNavigation() {
        val c = container(); val a = c.get()
        a.onLoadStateChange = { if (it == MWBLoadState.FAILED) a.load("file:///android_asset/index.html") }
        fail(a); assertNull(overlay(a)); assertEquals(MWBLoadState.LOADING, a.loadState)
        c.pause().stop().destroy()
    }
    @Test fun configureEveryContainerIncludingRecreation() {
        var configured = 0
        MWB.install(object : MWBHost { override fun configureContainer(container: MWBActivity) {
            configured++; assertEquals(MWBLoadState.IDLE, container.loadState)
            container.onGoHome = { }
        } })
        try {
            val c = container(); assertEquals(1, configured); c.recreate(); assertEquals(2, configured)
            val child = container(); assertEquals(3, configured)
            c.pause().stop().destroy(); child.pause().stop().destroy()
        } finally { MWB.install(object : MWBHost {}) }
    }
    @Test fun restrictedResourcesAndFiveSecondFallback() {
        val c = container(); val a = c.get(); fail(a)
        val error = views(a.window.decorView).filterIsInstance<WebView>().first { it !== a.webView }
        val client = shadowOf(error).webViewClient
        for (url in listOf("https://evil.test/a.js", "file:///etc/passwd", error.url!!.substringBeforeLast('/') + "/%2e%2e/index.html")) {
            val response = client.shouldInterceptRequest(error, request(url = url))!!
            assertEquals(403, response.statusCode)
        }
        assertTrue(client.shouldOverrideUrlLoading(error, request(url = "mwb-error-action://retry?session=old")))
        assertEquals(MWBLoadState.FAILED, a.loadState)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(4999)); assertNotNull(error.parent)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1)); assertNull(error.parent)
        assertTrue(button(a, "重新加载").isEnabled)
        c.pause().stop().destroy()
    }
    @org.robolectric.annotation.Config(sdk = [28])
    @Test fun rendererRecreationKeepsContainerOpen() {
        val c = container(); val a = c.get(); val view = a.webView!!
        val detail = object : android.webkit.RenderProcessGoneDetail() {
            override fun didCrash() = true
            override fun rendererPriorityAtExit() = 0
        }
        assertTrue(shadowOf(view).webViewClient.onRenderProcessGone(view, detail)); assertFalse(a.isFinishing)
        button(a, "重新加载").performClick(); assertNotSame(view, a.webView)
        c.pause().stop().destroy()
    }
}
