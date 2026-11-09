package com.mobilewebbridge

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 48 个 JS 方法中 30 个需要原生实现。 */
@RunWith(RobolectricTestRunner::class)
class BridgeTest {
    @Test fun mainThreadNavigationStartsWithoutWaitingForNextMessage() {
        // 主线程启动导航不应排到布局消息之后；否则首屏加载无谓等待。
        val activity = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        val view = wendu.dsbridge.DWebView(activity)
        view.loadUrl("https://example.test/first")
        assertEquals("https://example.test/first", view.url)
        view.loadUrl("https://example.test/second", mapOf("X-Demo" to "mwb"))
        assertEquals("https://example.test/second", view.url)
        assertEquals("mwb", org.robolectric.Shadows.shadowOf(view).lastAdditionalHttpHeaders["X-Demo"])
    }

    @Test fun backgroundNavigationStillDispatchesToMainThread() {
        // 后台调用仍须切回主线程，且保留请求头。
        val activity = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        val view = wendu.dsbridge.DWebView(activity)
        Thread { view.loadUrl("https://example.test/background", mapOf("X-Demo" to "worker")) }.apply { start(); join() }
        assertNull(view.url)
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("https://example.test/background", view.url)
        assertEquals("worker", org.robolectric.Shadows.shadowOf(view).lastAdditionalHttpHeaders["X-Demo"])
    }

    @Test fun laterMainThreadNavigationDoesNotGetOverwrittenByQueuedBackgroundNavigation() {
        // 混合线程连续导航仍按请求顺序执行，不能让旧后台请求覆盖较新的页面。
        for (backgroundHeaders in listOf(false, true)) for (mainHeaders in listOf(false, true)) {
            val activity = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
            val view = wendu.dsbridge.DWebView(activity)
            Thread {
                if (backgroundHeaders) view.loadUrl("https://example.test/old", mapOf("X-Demo" to "old"))
                else view.loadUrl("https://example.test/old")
            }.apply { start(); join() }
            if (mainHeaders) view.loadUrl("https://example.test/latest", mapOf("X-Demo" to "latest"))
            else view.loadUrl("https://example.test/latest")
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            assertEquals("https://example.test/latest", view.url)
            if (mainHeaders) assertEquals("latest", org.robolectric.Shadows.shadowOf(view).lastAdditionalHttpHeaders["X-Demo"])
        }
    }

    @Test fun nativeMethodManifestMatchesContract() {
        assertEquals(31, MWBBridgeAdapter.nativeMethods.size)
        assertTrue(MWBBridgeAdapter.nativeMethods.containsAll(setOf(
            "getAppInfoSync", "setStorageSync", "chooseImage", "openNativePage", "redirectTo")))
        // 移除能力后不再通过 DSBridge 暴露原生入口。
        assertFalse(MWBBridgeAdapter.nativeMethods.contains("addWaterMark"))
    }

    @Test fun resultEncoding() {
        assertEquals(0, MWBResult.success().getInt("errCode"))
        assertEquals(-1006, MWBResult.failure(-1006, "Untrusted page").getInt("errCode"))
    }
}
